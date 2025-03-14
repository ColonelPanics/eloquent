class PlayersController < ApplicationController
  before_action :set_player, only: [:edit, :destroy, :show, :update]

  def index
    @players = Player.order(:name)

    @players = @players.where('name LIKE ?', "#{params[:q]}%") if params[:q]

    respond_to do |f|
      f.html
      f.json { render json: @players.map { |p| { value: p.id, text: p.name } } }
    end
  end

  def create
    @player = Player.new(player_params)
    saved = @player.save

    respond_to do |f|
      f.html do
        if saved
          redirect_to players_path
        else
          render :new, status: :unprocessable_entity
        end
      end

      f.json do
        if saved
          render json: { text: @player.name, value: @player.id }
        else
          render json: { errors: @player.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end

  def update
    if @player.update(player_params)
      redirect_to player_path(@player)
    else
      redirect_to player_path(@player), status: :unprocessable_entity
    end
  end

  def destroy
    @player.destroy

    respond_to do |f|
      f.turbo_stream { render turbo_stream: turbo_stream.remove(@player) }
      f.html { redirect_to players_path }
    end
  end

  def edit
  end

  def new
    @player = Player.new
  end

  private

  def set_player
    @player = Player.find(params[:id])
  end

  def player_params
    params.require(:player).permit(:name, :email)
  end
end
