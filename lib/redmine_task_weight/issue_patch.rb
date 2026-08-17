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
        Rails.logger.warn "[redmine_task_weight] CustomField para Peso no fue encontrado."
        return
      end

      all_settings = (Setting.plugin_redmine_task_weight || {}).with_indifferent_access
      project_rules_all = all_settings[:project_rules] || {}
      project_settings = (project_rules_all[self.project_id] || project_rules_all[self.project_id.to_s] || {}).with_indifferent_access

      mode = project_settings[:mode] || 'factorial'

      # MODO MANUAL PURO: NO AUTOCALCULA NI SOBREESCRIBE NADA
      if mode == 'manual'
        Rails.logger.info "[redmine_task_weight] Issue ##{self.id || 'nuevo'}: Proyecto en Modo Manual. No se realiza cálculo automático."
        return
      end

      # 1. Calcular el peso automático para los atributos actuales
      auto_weight = compute_factorial_weight(self.project_id, self.tracker_id, self.category_id, self.priority_id)

      # 2. Obtener el valor ENVIADO/ACTUAL del campo en el issue (del formulario o de la BDD)
      submitted_val_str = self.custom_field_value(weight_field.id).to_s.strip
      if submitted_val_str.blank?
        cv = self.custom_values.find { |v| v.custom_field_id == weight_field.id }
        submitted_val_str = cv&.value.to_s.strip
      end

      if submitted_val_str.present?
        submitted_val_f = submitted_val_str.to_f

        # Si el valor enviado a mano es diferente del peso automático actual, es un OVERRIDE MANUAL
        if (submitted_val_f - auto_weight).abs > 0.01 && submitted_val_f > 0
          # Verificamos si era el peso automático viejo de antes de cambiar tracker/categoría/prioridad
          if self.persisted? && (self.tracker_id_changed? || self.category_id_changed? || self.priority_id_changed?)
            old_tracker_id  = self.respond_to?(:tracker_id_before_last_save)  && self.tracker_id_before_last_save  || (self.respond_to?(:tracker_id_was)  ? self.tracker_id_was  : self.tracker_id)
            old_category_id = self.respond_to?(:category_id_before_last_save) && self.category_id_before_last_save || (self.respond_to?(:category_id_was) ? self.category_id_was : self.category_id)
            old_priority_id = self.respond_to?(:priority_id_before_last_save) && self.priority_id_before_last_save || (self.respond_to?(:priority_id_was) ? self.priority_id_was : self.priority_id)

            old_auto_weight = compute_factorial_weight(self.project_id, old_tracker_id, old_category_id, old_priority_id)

            # Si el valor enviado coincidía exactamente con el peso automático viejo, no era un override manual del usuario
            if (submitted_val_f - old_auto_weight).abs < 0.01
              assign_weight_value(weight_field, auto_weight)
              return
            end
          end

          # Si llegó hasta acá, es un valor puesto manualmente por el usuario -> Respetarlo y NO pisarlo
          Rails.logger.info "[redmine_task_weight] Issue ##{self.id || 'nuevo'}: Prevalece valor manual enviado '#{submitted_val_f}' (auto calculaba #{auto_weight})."
          return
        end
      end

      # Asignar peso automático por defecto
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
      Rails.logger.info "[redmine_task_weight] Asignando peso automático para Issue ##{self.id || 'nuevo'}: #{formatted_str}"
      self.custom_field_values = { weight_field.id.to_s => formatted_str }
      cv = self.custom_values.find { |v| v.custom_field_id == weight_field.id } || self.custom_values.build(custom_field: weight_field)
      cv.value = formatted_str
    end
  end
end
