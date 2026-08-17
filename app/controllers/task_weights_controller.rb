class TaskWeightsController < ApplicationController
  before_action :find_project_by_project_id, only: [:index]
  before_action :authorize, only: [:index]

  def index
    @period = params[:period].presence || 'this_month'
    @period_date_range = case @period
                         when 'last_30_days'
                           30.days.ago.beginning_of_day..Time.current
                         when 'this_year'
                           Date.today.beginning_of_year.beginning_of_day..Date.today.end_of_year.end_of_day
                         when 'all_time'
                           nil
                         else # 'this_month'
                           Date.today.beginning_of_month.beginning_of_day..Date.today.end_of_month.end_of_day
                         end

    weight_field = find_weight_custom_field

    @user_stats = {} # { user_name => { open_count: 0, open_weight: 0.0, closed_count: 0, closed_weight: 0.0 } }

    # 1. Tareas Abiertas (Carga Pendiente Actual)
    open_statuses = IssueStatus.where(is_closed: false).pluck(:id)
    open_issues = @project.issues.where(status_id: open_statuses)

    open_issues.includes(:assigned_to, :custom_values).find_each do |issue|
      user_name = issue.assigned_to ? issue.assigned_to.name : l(:label_unassigned)
      weight_val = extract_issue_weight(issue, weight_field)

      @user_stats[user_name] ||= { open_count: 0, open_weight: 0.0, closed_count: 0, closed_weight: 0.0 }
      @user_stats[user_name][:open_count] += 1
      @user_stats[user_name][:open_weight] += weight_val
    end

    # 2. Tareas Cerradas (Score de Puntos Resueltos en el Período)
    closed_statuses = IssueStatus.where(is_closed: true).pluck(:id)
    closed_issues = @project.issues.where(status_id: closed_statuses)
    if @period_date_range
      if Issue.column_names.include?('closed_on')
        closed_issues = closed_issues.where(closed_on: @period_date_range)
      else
        closed_issues = closed_issues.where(updated_on: @period_date_range)
      end
    end

    closed_issues.includes(:assigned_to, :custom_values).find_each do |issue|
      user_name = issue.assigned_to ? issue.assigned_to.name : l(:label_unassigned)
      weight_val = extract_issue_weight(issue, weight_field)

      @user_stats[user_name] ||= { open_count: 0, open_weight: 0.0, closed_count: 0, closed_weight: 0.0 }
      @user_stats[user_name][:closed_count] += 1
      @user_stats[user_name][:closed_weight] += weight_val
    end

    # 3. Métricas Resumen KPI
    @total_open_issues = @user_stats.values.sum { |s| s[:open_count] }
    @total_open_weight = @user_stats.values.sum { |s| s[:open_weight] }.round(1)

    active_users = @user_stats.select { |k, v| k != l(:label_unassigned) && v[:open_count] > 0 }
    @active_user_count = active_users.size
    @avg_open_weight_per_user = @active_user_count > 0 ? (@total_open_weight.to_f / @active_user_count).round(1) : 0.0

    top_user_pair = active_users.max_by { |k, v| v[:open_weight] }
    @top_loaded_user = top_user_pair ? top_user_pair[0] : nil
    @top_loaded_weight = top_user_pair ? top_user_pair[1][:open_weight].round(1) : 0.0

    @total_closed_issues = @user_stats.values.sum { |s| s[:closed_count] }
    @total_closed_weight = @user_stats.values.sum { |s| s[:closed_weight] }.round(1)
  end

  private

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

  def extract_issue_weight(issue, weight_field)
    return 1.0 unless weight_field

    cv = issue.custom_values.find { |v| v.custom_field_id == weight_field.id }
    return 1.0 unless cv && cv.value.present?

    val = cv.value.to_f
    val > 0 ? val : 1.0
  end
end