class ResultService
  def self.create(game, params)
    result = game.results.build

    teams = (params[:teams] || {}).values.each.with_object([]) do |team, acc|
      players = Array.wrap(team[:players]).delete_if(&:blank?)
      acc << { players: players }
    end

    teams = teams.reverse.drop_while{ |team| team[:players].empty? }.reverse

    teams.each do |team|
      result.teams.build player_ids: team[:players]
    end

    result.for = params[:for]
    result.against = params[:against]

    unless result.tie?
      result.winteam.winner = true
      result.loseteam.winner = false
    end

    if result.valid?
      Result.transaction do
        game.rater.update_ratings game, result

        result.save!

        OpenStruct.new(
          success?: true,
          result: result
        )
      end
    else
      OpenStruct.new(
        success?: false,
        result: result
      )
    end
  end

  def self.destroy(result)
    return OpenStruct.new(success?: false) unless result.most_recent?

    Result.transaction do
      result.players.each do |player|
        player.rewind_rating!(result.game)
      end

      result.destroy

      OpenStruct.new(success?: true)
    end
  end
end
