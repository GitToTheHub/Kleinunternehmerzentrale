# Jede Besucherin und jeder Besucher arbeitet im eigenen Bereich. Er wird beim ersten Speichern angelegt und
# über ein signiertes Cookie wiedererkannt. Mit einem Konto ist er auch auf anderen Geräten erreichbar.
module CurrentWorkspace
  extend ActiveSupport::Concern

  COOKIE = :workspace

  included do
    helper_method :current_workspace, :workspace?
  end

  private

  def current_workspace
    return @current_workspace if defined?(@current_workspace)

    token = cookies.signed[COOKIE]
    @current_workspace = token && Workspace.find_by(token: token)
    @current_workspace&.touch_activity
    @current_workspace
  end

  def workspace?
    current_workspace.present?
  end

  # Legt bei Bedarf einen Gast-Bereich an, damit die App ohne Anmeldung sofort nutzbar ist.
  def workspace!
    current_workspace || start_workspace(Workspace.create!)
  end

  def start_workspace(workspace)
    @current_workspace = workspace
    cookies.signed[COOKIE] = {
      value: workspace.token, expires: 1.year.from_now, httponly: true, same_site: :lax, secure: Rails.env.production?
    }
    workspace
  end

  def end_workspace
    cookies.delete(COOKIE)
    @current_workspace = nil
  end
end
