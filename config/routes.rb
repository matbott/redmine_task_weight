resources :projects do
  get 'task_weight_report', to: 'task_weights#index'
end