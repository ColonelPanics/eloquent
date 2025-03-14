class ResultsController < ApplicationController
  before_action :set_game

  helper_method :team_game?

  def create
    response = ResultService.create(@game, params[:result])

    if response.success?
      redirect_to game_path(@game)
    else
      @result = response.result
      @result.teams.build while @result.teams.length < max_number_of_teams
      render :new, status: 422
    end
  end

  def destroy
    result = @game.results.find_by_id(params[:id])
    ResultService.destroy(result)
    redirect_to request.referer
  end

  def new
    @result = Result.new
    max_number_of_teams.times{@result.teams.build}
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def team_game?
    set_game
    @game.max_number_of_players_per_team != 1
  end

  def max_number_of_teams
    @game.max_number_of_teams || 20
  end
end
