module RedmineTaskWeight
  module IssuePatch
    extend ActiveSupport::Concern

    included do
      before_save :calculate_and_assign_weight
    end

    private

    def calculate_and_assign_weight
      unless self.project && self.project.module_enabled?(:task_weight)
        return
      end

      weight_field = find_weight_custom_field
      unless weight_field
        Rails.logger.warn '[redmine_task_weight] Task Weight custom field was not found.'
        return
      end

      all_settings = (Setting.plugin_redmine_task_weight || {}).with_indifferent_access
      project_rules_all = all_settings[:project_rules] || {}
      project_settings = (project_rules_all[self.project_id] || project_rules_all[self.project_id.to_s] || {}).with_indifferent_access

      mode = project_settings[:mode] || 'factorial'

      # Manual mode never calculates or overwrites a weight.
      if mode == 'manual'
        Rails.logger.info "[redmine_task_weight] Issue ##{self.id || 'new'}: project is in manual mode; skipping automatic calculation."
        return
      end

      # 1. Calculate the automatic weight for the current attributes.
      auto_weight = compute_factorial_weight(self.project_id, self.tracker_id, self.category_id, self.priority_id)

      # 2. Read the previously stored value, if the issue already exists.
      saved_cv = self.custom_values.find { |v| v.custom_field_id == weight_field.id }
      saved_val_str = (saved_cv&.respond_to?(:value_was) && saved_cv.value_was.present? ? saved_cv.value_was : saved_cv&.value).to_s.strip

      # 3. Read the value submitted in the current request.
      submitted_val_str = self.custom_field_value(weight_field.id).to_s.strip

      # Case A: editing an existing issue.
      if self.persisted?
        # Check whether any factor used by the calculation changed.
        tracker_changed  = self.respond_to?(:tracker_id_changed?)  && self.tracker_id_changed?
        category_changed = self.respond_to?(:category_id_changed?) && self.category_id_changed?
        priority_changed = self.respond_to?(:priority_id_changed?) && self.priority_id_changed?

        extra_cf_changed = false
        extra_cf_id = project_settings[:custom_field_id]
        if extra_cf_id.present?
          extra_cv = self.custom_values.find { |v| v.custom_field_id == extra_cf_id.to_i }
          extra_cf_changed = extra_cv&.respond_to?(:value_changed?) && extra_cv.value_changed?
        end

        factors_changed = tracker_changed || category_changed || priority_changed || extra_cf_changed

        # When factors did not change (for example, only notes or status changed):
        unless factors_changed
          # Preserve an explicit weight submitted by an authorized user.
          if submitted_val_str.present? && submitted_val_str != saved_val_str
            Rails.logger.info "[redmine_task_weight] Issue ##{self.id}: weight manually updated to '#{submitted_val_str}'."
            return
          end

          # Keep an existing stored value without recalculating it.
          if saved_val_str.present?
            Rails.logger.info "[redmine_task_weight] Issue ##{self.id}: factors unchanged; keeping existing weight '#{saved_val_str}'."
            return
          end
        end

        # When factors changed (tracker, category, priority, or extra field):
        if factors_changed
          # Preserve an explicit submitted value when it differs from the automatic result.
          if submitted_val_str.present? && submitted_val_str != saved_val_str && (submitted_val_str.to_f - auto_weight).abs > 0.01
            Rails.logger.info "[redmine_task_weight] Issue ##{self.id}: factors changed, but a manual weight '#{submitted_val_str}' was submitted."
            return
          end

          # Determine whether the stored value was a previous manual override.
          if saved_val_str.present?
            saved_val_f = saved_val_str.to_f
            old_tracker_id  = (self.respond_to?(:tracker_id_before_last_save) && self.tracker_id_before_last_save) || (self.respond_to?(:tracker_id_was) ? self.tracker_id_was : self.tracker_id)
            old_category_id = (self.respond_to?(:category_id_before_last_save) && self.category_id_before_last_save) || (self.respond_to?(:category_id_was) ? self.category_id_was : self.category_id)
            old_priority_id = (self.respond_to?(:priority_id_before_last_save) && self.priority_id_before_last_save) || (self.respond_to?(:priority_id_was) ? self.priority_id_was : self.priority_id)

            old_auto_weight = compute_factorial_weight(self.project_id, old_tracker_id, old_category_id, old_priority_id)

            # A value that differs from the previous automatic result is a manual override.
            if (saved_val_f - old_auto_weight).abs > 0.01 && saved_val_f > 0
              Rails.logger.info "[redmine_task_weight] Issue ##{self.id}: keeping manual override '#{saved_val_f}' after factor changes."
              return
            end
          end
        end
      end

      # Case B: creating a new issue.
      if self.new_record? && submitted_val_str.present?
        submitted_val_f = submitted_val_str.to_f
        if (submitted_val_f - auto_weight).abs > 0.01 && submitted_val_f > 0
          Rails.logger.info "[redmine_task_weight] New issue: preserving submitted manual weight '#{submitted_val_f}'."
          return
        end
      end

      # Assign the automatic weight by default.
      assign_weight_value(weight_field, auto_weight)
    end

    def compute_factorial_weight(proj_id, trk_id, cat_id_val, prio_id_val)
      all_settings = (Setting.plugin_redmine_task_weight || {}).with_indifferent_access
      project_rules_all = all_settings[:project_rules] || {}
      project_settings = (project_rules_all[proj_id] || project_rules_all[proj_id.to_s] || {}).with_indifferent_access

      mode = project_settings[:mode] || 'factorial'

      if mode == 'priority'
        prio_factors = (project_settings[:priority_factors] || {}).with_indifferent_access
        if prio_id_val.present? && prio_factors[prio_id_val.to_s].present?
          return prio_factors[prio_id_val.to_s].to_f
        elsif self.priority
          return self.priority.position.to_f
        end
        return 1.0
      end

      # Mode factorial
      tracker_factors = (project_settings[:tracker_factors] || {}).with_indifferent_access
      tracker_f = (trk_id.present? && tracker_factors[trk_id.to_s].present?) ? tracker_factors[trk_id.to_s].to_f : 1.0

      cat_factors = (project_settings[:category_factors] || {}).with_indifferent_access
      c_id = cat_id_val.present? ? cat_id_val.to_s : '0'
      cat_f = (cat_factors[c_id] || 1.0).to_f

      prio_factors = (project_settings[:priority_factors] || {}).with_indifferent_access
      prio_f = if prio_id_val.present? && prio_factors[prio_id_val.to_s].present?
                 prio_factors[prio_id_val.to_s].to_f
               elsif self.priority
                 self.priority.position.to_f
               else
                 1.0
               end

      custom_cf_f = 1.0
      extra_cf_id = project_settings[:custom_field_id]
      if extra_cf_id.present?
        extra_cv = self.custom_values.find { |v| v.custom_field_id == extra_cf_id.to_i }
        if extra_cv && extra_cv.value.present?
          val = extra_cv.value.to_s.strip
          cf_factors_all = (project_settings[:custom_field_factors] || {}).with_indifferent_access
          cf_factors = (cf_factors_all[extra_cf_id] || {}).with_indifferent_access

          if cf_factors[val].present?
            custom_cf_f = cf_factors[val].to_f
          elsif val.match?(/\A-?\d+(\.\d+)?\z/) && val.to_f > 0
            custom_cf_f = val.to_f
          end
        end
      end

      (tracker_f * cat_f * prio_f * custom_cf_f).round(2)
    end

    def format_weight(val)
      f = val.to_f
      (f % 1 == 0) ? f.to_i.to_s : f.round(2).to_s
    end

    def find_weight_custom_field
      all_settings = (Setting.plugin_redmine_task_weight || {}).with_indifferent_access
      target_id = all_settings[:weight_custom_field_id]

      if target_id.present?
        field = IssueCustomField.find_by(id: target_id.to_i)
        return field if field
      end

      IssueCustomField.find_by(name: 'Peso de la Tarea') ||
      IssueCustomField.find_by(name: 'Task Weight') ||
      IssueCustomField.find_by(name: 'Peso') ||
      IssueCustomField.find_by(name: 'Weight')
    end

    def assign_weight_value(weight_field, weight_val)
      formatted_str = format_weight(weight_val)
      Rails.logger.info "[redmine_task_weight] Assigning automatic weight to issue ##{self.id || 'new'}: #{formatted_str}"
      self.custom_field_values = { weight_field.id.to_s => formatted_str }
      cv = self.custom_values.find { |v| v.custom_field_id == weight_field.id } || self.custom_values.build(custom_field: weight_field)
      cv.value = formatted_str
    end
  end
end
