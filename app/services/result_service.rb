class ResultService
  def self.create(game, params)
    result = game.results.build

    teams = (params[:teams] || {}).values.each.with_object([]) do |team, acc|
      players = Array.wrap(team[:players]).delete_if(&:blank?)
      acc << { players: players, score: team[:score] }
    end

    teams = teams.reverse.drop_while{ |team| team[:players].empty? }.reverse

    teams = teams.sort { |a, b| b[:score] <=> a[:score] }

    prev_score = nil
    current_rank = Team::FIRST_PLACE_RANK

    teams.each do |team|
      current_rank += 1 if prev_score && team[:score] < prev_score

      result.teams.build(
        player_ids: team[:players],
        rank: current_rank,
        score: team[:score]
      )

      prev_score = team[:score]
    end

    if result.valid?
      Result.transaction do
        game.rater.update_ratings(game, result)

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
