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

      weight_field = IssueCustomField.find_by(name: 'Peso de la Tarea') || IssueCustomField.find_by(name: 'Peso')
      unless weight_field
        Rails.logger.warn "[redmine_task_weight] CustomField 'Peso de la Tarea' no fue encontrado."
        return
      end

      # Si el usuario modificó manualmente el peso en este guardado, lo respetamos
      cv_existing = self.custom_values.find { |v| v.custom_field_id == weight_field.id }
      if cv_existing && cv_existing.value_changed? && cv_existing.value.present?
        Rails.logger.info "[redmine_task_weight] Issue ##{self.id || 'nuevo'}: Respetando valor manual '#{cv_existing.value}'."
        return
      end

      all_settings = (Setting.plugin_redmine_task_weight || {}).with_indifferent_access
      project_rules_all = all_settings[:project_rules] || {}
      project_settings = (project_rules_all[self.project_id] || project_rules_all[self.project_id.to_s] || {}).with_indifferent_access

      mode = project_settings[:mode] || 'factorial'

      calculated_weight = 1.0

      if mode == 'priority'
        prio_factors = (project_settings[:priority_factors] || {}).with_indifferent_access
        if self.priority_id.present? && prio_factors[self.priority_id.to_s].present?
          calculated_weight = prio_factors[self.priority_id.to_s].to_f
        elsif self.priority
          calculated_weight = self.priority.position.to_f
        end
      elsif mode == 'factorial'
        # 1. Factor Tracker
        tracker_factors = (project_settings[:tracker_factors] || {}).with_indifferent_access
        tracker_f = if self.tracker_id.present? && tracker_factors[self.tracker_id.to_s].present?
                      tracker_factors[self.tracker_id.to_s].to_f
                    else
                      1.0
                    end

        # 2. Factor Categoría
        cat_factors = (project_settings[:category_factors] || {}).with_indifferent_access
        cat_id = self.category_id.present? ? self.category_id.to_s : '0'
        cat_f = (cat_factors[cat_id] || 1.0).to_f

        # 3. Factor Prioridad
        prio_factors = (project_settings[:priority_factors] || {}).with_indifferent_access
        prio_f = if self.priority_id.present? && prio_factors[self.priority_id.to_s].present?
                   prio_factors[self.priority_id.to_s].to_f
                 elsif self.priority
                   self.priority.position.to_f
                 else
                   1.0
                 end

        # 4. Factor Campo Personalizado Adicional
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

        calculated_weight = (tracker_f * cat_f * prio_f * custom_cf_f).round(2)
      end

      Rails.logger.info "[redmine_task_weight] Calculando peso para Issue ##{self.id || 'nuevo'} (Proyecto ##{self.project_id}): Mode=#{mode}, Weight=#{calculated_weight}"

      self.custom_field_values = { weight_field.id.to_s => calculated_weight.to_s }
      cv = self.custom_values.find { |v| v.custom_field_id == weight_field.id } || self.custom_values.build(custom_field: weight_field)
      cv.value = calculated_weight.to_s
    end
  end
end
