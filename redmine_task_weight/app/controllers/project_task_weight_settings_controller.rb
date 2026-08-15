class ProjectTaskWeightSettingsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  def save
    settings = (Setting.plugin_redmine_task_weight || {}).deep_dup
    settings['project_rules'] ||= {}
    
    settings['project_rules'][@project.id.to_s] = {
      'mode' => params[:mode],
      'rules' => params[:rules] || {}
    }

    Setting.plugin_redmine_task_weight = settings
    flash[:notice] = l(:notice_successful_update)
    redirect_to settings_project_path(@project, tab: 'task_weight')
  end
end