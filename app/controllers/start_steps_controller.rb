class StartStepsController < ApplicationController
  def update
    workspace!.toggle_step(params[:key])
    redirect_back_or_to root_path
  end
end
