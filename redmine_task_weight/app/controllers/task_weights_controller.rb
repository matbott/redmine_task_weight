class TaskWeightsController < ApplicationController
  before_action :find_project_by_project_id, only: [:index]
  before_action :authorize, only: [:index]

  def index
    weight_field = IssueCustomField.find_by(name: 'Peso de la Tarea') || IssueCustomField.find_by(name: 'Peso')

    unless weight_field
      flash.now[:error] = l(:error_weight_field_not_found)
      @user_weights = {}
      return
    end

    open_issues = @project.issues.where(status_id: IssueStatus.where(is_closed: false).select(:id))
    @user_weights = {}

    open_issues.includes(:assigned_to, :custom_values).find_each do |issue|
      user = issue.assigned_to ? issue.assigned_to.name : l(:label_unassigned)
      cv = issue.custom_values.find { |v| v.custom_field_id == weight_field.id }
      weight_val = cv ? cv.value.to_f : 0.0

      @user_weights[user] ||= { total_weight: 0.0, issue_count: 0 }
      @user_weights[user][:total_weight] += weight_val
      @user_weights[user][:issue_count] += 1
    end
  end
end