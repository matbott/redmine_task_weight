require File.expand_path('../lib/redmine_task_weight/hooks', __FILE__)
require File.expand_path('../lib/redmine_task_weight/issue_patch', __FILE__)

# Apply the Issue patch for automatic weight calculation.
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
  description 'Automatically calculate issue workload weights using configurable per-project factors.'
  version '1.3.3'


  # Global plugin settings under Administration -> Plugins -> Configure.
  settings default: { 'project_rules' => {} }, partial: 'settings/redmine_task_weight_settings'

  # Project module that enables the workload report for each project.
  project_module :task_weight do
    permission :view_task_weight_report, { task_weights: [:index] }, read: true
  end

  # Project report menu entry.
  menu :project_menu,
       :task_weight_report,
       { controller: 'task_weights', action: 'index' },
       caption: :label_task_weight_report,
       param: :project_id,
       permission: :view_task_weight_report,
       after: :issues
end


# Create the hidden custom field when Redmine starts, if needed.
Rails.configuration.after_initialize do
  begin
    if CustomField.table_exists?
      field_name = 'Task Weight'

      unless IssueCustomField.exists?(name: ['Peso de la Tarea', 'Task Weight', 'Peso', 'Weight'])
        IssueCustomField.create!(
          name: field_name,
          field_format: 'float',
          is_required: false,
          is_for_all: false,
          is_filter: true,
          visible: false, # Hidden from regular users to prevent manual manipulation.
          default_value: '1',
          description: 'Hidden field managed automatically by redmine_task_weight'
        )
        Rails.logger.info "[redmine_task_weight] Custom field '#{field_name}' created automatically."
      end
    end
  rescue => e
    Rails.logger.error "[redmine_task_weight] Error while checking the custom field: #{e.message}"
  end
end
