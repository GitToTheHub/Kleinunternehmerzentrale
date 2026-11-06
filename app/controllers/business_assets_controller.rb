class BusinessAssetsController < ApplicationController
  before_action :set_asset, only: %i[edit update destroy]

  def index
    @assets = current_workspace ? current_workspace.business_assets.includes(:asset_depreciations, :asset_private_uses).order(:acquired_on, :id) : BusinessAsset.none
  end

  def new
    @asset = BusinessAsset.new(acquired_on: Date.current, paid_on: Date.current, useful_life: 3)
    build_schedule_row
  end

  def create
    @asset = workspace!.business_assets.new(asset_params)
    if @asset.workspace.with_lock { @asset.save }
      redirect_to business_assets_path, notice: "Anlagegut gespeichert."
    else
      build_schedule_row
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    build_schedule_row
  end

  def update
    if @asset.workspace.with_lock { @asset.update(asset_params) }
      redirect_to business_assets_path, notice: "Anlagegut aktualisiert."
    else
      build_schedule_row
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @asset.destroy!
    redirect_to business_assets_path, notice: "Anlagegut gelöscht.", status: :see_other
  end

  private

  def build_schedule_row
    @asset.asset_private_uses.build if @asset.asset_private_uses.none?(&:new_record?)
    @asset.asset_depreciations.build if @asset.asset_depreciations.none?(&:new_record?)
  end

  def set_asset
    @asset = (current_workspace ? current_workspace.business_assets : BusinessAsset.none).find(params[:id])
  end

  def asset_params
    params.require(:business_asset).permit(:name, :reference, :acquired_on, :origin, :category, :cost,
      :depreciation_method, :useful_life, :gwg_net_value, :paid_on, :payment_account,
      :disposed_on, :disposal_kind, :withdrawal_value, :disposal_recognized_on, :notes, :business_use_percent, :usage_basis,
      asset_depreciations_attributes: %i[id year amount special_amount reason _destroy],
      asset_private_uses_attributes: %i[id year business_percent basis calculation_mode manual_amount _destroy])
  end
end
