require File.expand_path('../lib/redmine_task_weight/hooks', __FILE__)
require File.expand_path('../lib/redmine_task_weight/issue_patch', __FILE__)

# Aplicar parche de Issue para cálculo automático de pesos
def apply_task_weight_patches
  unless Issue.included_modules.include?(RedmineTaskWeight::IssuePatch)
    Issue.include(RedmineTaskWeight::IssuePatch)
  end
end

apply_task_weight_patches

if defined?(ActiveSupport::Reloader)
  ActiveSupport::Reloader.to_prepare do
    apply_task_weight_patches
  end
elsif Rails.configuration.respond_to?(:to_prepare)
  Rails.configuration.to_prepare do
    apply_task_weight_patches
  end
end

Redmine::Plugin.register :redmine_task_weight do
  name 'Redmine Task Weight Plugin'
  author 'matbott & 🤖'
  author_url 'https://github.com/matbott/redmine_task_weight'
  url 'https://github.com/matbott/redmine_task_weight'
  description 'Cálculo de peso automático de tareas por Fórmula Factorial por proyecto.'
  version '1.3.0'


  # Configuración global del plugin en Administración -> Plugins -> Configurar
  settings default: { 'project_rules' => {} }, partial: 'settings/redmine_task_weight_settings'

  # Módulo de proyecto activable individualmente para el reporte
  project_module :task_weight do
    permission :view_task_weight_report, { task_weights: [:index] }, read: true
  end

  # Menú de reportes del proyecto
  menu :project_menu,
       :task_weight_report,
       { controller: 'task_weights', action: 'index' },
       caption: :label_task_weight_report,
       param: :project_id,
       permission: :view_task_weight_report,
       after: :issues
end


# Autocreación del Custom Field Oculto al iniciar Redmine
Rails.configuration.after_initialize do
  begin
    if CustomField.table_exists?
      field_name = 'Peso de la Tarea'

      unless IssueCustomField.exists?(name: field_name)
        IssueCustomField.create!(
          name: field_name,
          field_format: 'float',
          is_required: false,
          is_for_all: true,
          is_filter: true,
          visible: false, # Oculto para usuarios comunes (anti-trampas)
          default_value: '1.0',
          description: 'Campo oculto administrado automáticamente por redmine_task_weight'
        )
        Rails.logger.info "[redmine_task_weight] CustomField '#{field_name}' creado automáticamente."
      end
    end
  rescue => e
    Rails.logger.error "[redmine_task_weight] Error al verificar CustomField: #{e.message}"
  end
end

