Rails.application.routes.draw do
  get '/' => 'liff#index'

  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  post '/callback' => 'linebot#callback'
end
