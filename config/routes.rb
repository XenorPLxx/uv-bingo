Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "events#index"
  get "sign-in", to: "sessions#new", as: :sign_in
  get "login", to: "sessions#capture"
  get "login/confirm", to: "sessions#confirm", as: :confirm_login
  post "login/confirm", to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  post "discord/interactions", to: "discord#create"
  resources :events, path: "e", only: :show do
    member do
      get :presentation
      get :reveal
      get :state
      get :draw_record
    end
    resources :options, only: :create
    resources :votes, only: [ :create, :destroy ]
    resources :proposals, only: :create
  end
  namespace :admin do
    root "events#index"
    resources :events, only: [ :index, :show, :new, :create, :update ] do
      member do
        post :draw
        post :transition
        post :moderate
        post :mark
      end
    end
  end
  mount ActionCable.server => "/cable"
end
