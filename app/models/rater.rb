module Rater
  class EloRater
    DefaultValue = 1000

    def default_attributes
      { value: DefaultValue }
    end

    def description
      "Elo (1v1 only)"
    end

    def validate_game game
      if game.min_number_of_teams != 2 ||
         game.max_number_of_teams != 2 ||
         game.min_number_of_players_per_team != 1 ||
         game.max_number_of_players_per_team != 1
        game.errors.add(:rating_type, "Elo can only be used with 1v1 games")
      end
    end

    def update_ratings game, result
      teams = result.teams

      if result.tie?
        first_rating, second_rating = result.winners
          .map{ |player| player.ratings.find_or_create(game) }

        first_elo = to_elo(first_rating)
        second_elo = to_elo(second_rating)

        first_elo.plays_draw(second_elo)
      else
        winner = result.winners.first
        loser = result.losers.first

        first_rating = winner.ratings.find_or_create(game)
        second_rating = loser.ratings.find_or_create(game)

        first_elo = to_elo(first_rating)
        second_elo = to_elo(second_rating)

        match = first_elo.versus(second_elo)
        # Skew value based on margin of victory
        ## The 'result' can be from 0 to 1:
        ##   1 - player one wins (what happens here)
        ##   0.5 - it is a draw
        ## Knowing this we can skew the result towards 0.5 in situations
        ## where the margin of victory is smaller.
        ##
        ## Based on how this system works (first_elo is always the winner) we
        ## can assume that 'for' is larger than 'against' and use that to generate
        ## a value with which the result can be skewed
        ##
        ## Foosball
        ## 10-0 = 10 should become 1, a perfect victory
        ## 9-1 = 8
        ## 6-4 = 2 should be closer to 0.5, a narrow victory
        ##
        ## Ping Pong
        ## 11-0 = 11 should become 1, a perfect victory
        ## 11-5 = 6
        ## 11-9 = 2 should be closer to 0.5, a narrow victory
        ##
        ## Use 'for' as 100% and get the scale of points conceded 'against'
        ## and then divide by 2 so that the value will never be 0.5 or above
        ## because if it divided by 2 and became 0.5 then it was a draw!
        ## result = 1 - ((against / for) / 2)
        ##   10-0 = 1 - ((0 / 10)  / 2)= 1 - 0 = 1, a perfect victory
        ##   6-4 = 1 - ((4 / 6) / 2) = 1 - 0.3 = 0.7, a narrow victory
        ##
        ## Testing with a blank database and first match between "one" and "two"
        ##   "one" defeats "two" 10-0: one elo 1012, two elo 987
        ##   "one" defeats "two" 6-4: one elo 1004, two elo 995
        #

        winner_score = result.winning_teams.first.score
        loser_score = result.losing_teams.first.score

        skew = (loser_score / winner_score).to_f / 2
        match.result = 1 - skew
      end

      _update_rating_from_elo(first_rating, first_elo, result)
      _update_rating_from_elo(second_rating, second_elo, result)
    end

    def to_elo rating
      Elo::Player.new(
        rating: rating.value,
        games_played: rating.player.results.where(game_id: rating.game.id).count,
        pro: rating.pro?
      )
    end

    def _update_rating_from_elo(rating, elo, result)
      Rating.transaction do
        rating.update!(value: elo.rating, pro: elo.pro?)
        rating.history_events.create!(value: elo.rating, created_at: result.created_at || DateTime.now)
      end
    end
  end

  class TrueSkillRater
    DefaultValue = 0
    DefaultMean = 25
    DefaultDeviation = 25.0/3.0

    def default_attributes
      { value: DefaultValue, trueskill_mean: DefaultMean, trueskill_deviation: DefaultDeviation }
    end

    def description
      "Trueskill"
    end

    def validate_game game
    end

    # XXX This only works for two-team games
    def update_ratings(game, result)
      teams = result.teams

      # Get the arrays of players on each team
      first_team = teams.first.players.map{|player| player.ratings.find_or_create(game)}
      second_team = teams.last.players.map{|player| player.ratings.find_or_create(game)}

      # Identify the point skew between the 2 teams
      first_scorediff = teams.first.score - teams.last.score
      second_scorediff = teams.last.score - teams.first.score

      # Create a hash of the results
      ratings_to_scorediff = { first_team => first_scorediff.to_f, second_team => second_scorediff.to_f }

      # Build up the trueskill hash for ingestion
      ratings_to_trueskill = {}
      trueskills_to_scorediff = ratings_to_scorediff.each_with_object({}) do |(ratings, scorediff), hash|
        trueskills = ratings.map do |rating|
          ratings_to_trueskill[rating] = to_trueskill(rating)
        end

        hash[trueskills] = scorediff
      end

      # Calculate skill change from score difference
      graph = TrueskillScoreBasedBayesianFixed.new trueskills_to_scorediff
      graph.update_skills

      # Update ratings from Trueskill calculations
      trueskills_to_scorediff.each do |team, score|
        team.each do |trueskill|
          # Locate the corresponding Rating for this TrueskillRating
          rating = (first_team + second_team).select { |rating| rating.player_id == trueskill.player_id }.first
          # Update Rating for player from TrueskillRating
          _update_rating_from_trueskill rating, trueskill, result
        end
      end
    end

    def to_trueskill rating
      trueskill_rating = Saulabs::TrueSkill::Rating.new(
        rating.trueskill_mean,
        rating.trueskill_deviation
      )
      trueskill_rating.player_id = rating.player_id
      return trueskill_rating
    end

    def _update_rating_from_trueskill rating, trueskill, result
      Rating.transaction do
        attributes = { value: (trueskill.mean - (3.0 * trueskill.deviation)) * 100,
                       trueskill_mean: trueskill.mean,
                       trueskill_deviation: trueskill.deviation,
                       created_at: result.created_at || DateTime.now }
        rating.update! attributes
        rating.history_events.create! attributes
      end
    end
  end

  # Add player_id to TrueSkill rating class
  class Saulabs::TrueSkill::Rating
    attr_accessor :player_id
  end

  # Make sure player_id persists through the magic/madness of skill calculation
  ## Unlike Saulabs::TrueSkill::FactorGraph this method *does not* update the TrueSkill
  ## Rating objects in-place which means the hash we use to track which player rating
  ## relates to which TrueSkill Rating (ratings_to_trueskill) does not get the shift
  ## when we 'update_graph'
  class TrueskillScoreBasedBayesianFixed < Saulabs::TrueSkill::ScoreBasedBayesianRating
    def update_skills
      n_team_1    = @skills_additive ? 1 : @teams[0].size.to_f
      n_team_2    = @skills_additive ? 1 : @teams[1].size.to_f

      n_all       = @teams[0].size.to_f + @teams[1].size.to_f
      var_team_1  = @teams[0].inject(0){|sum,item| sum + item.variance}
      var_team_2  = @teams[1].inject(0){|sum,item| sum + item.variance}
      mean_team_1 = @teams[0].inject(0){|sum,item| sum + item.mean}
      mean_team_2 = @teams[1].inject(0){|sum,item| sum + item.mean}


      @teams[0].map!{|rating|
        precision = 1.0 / rating.variance + 1.0/ ( n_all * @beta_squared + 2.0 * @gamma_squared + var_team_2 / n_team_2 + var_team_1 / n_team_1 - rating.variance / n_team_1)
        precision_mean = rating.mean / rating.variance + (@scores[0] - @scores[1] + n_team_1 * (mean_team_2 / n_team_2 - mean_team_1 / n_team_1 + rating.mean / n_team_1)) / ( n_all * @beta_squared + 2.0 * @gamma_squared + var_team_2 / n_team_2 + var_team_1 / n_team_1 - rating.variance / n_team_1)
        partial_updated_precision = rating.precision + rating.activity*( precision - rating.precision)
        partial_updated_precision_mean =  rating.precision_mean + rating.activity * (precision_mean - rating.precision_mean)
        newrating = Saulabs::TrueSkill::Rating.new(partial_updated_precision_mean / partial_updated_precision, ( 1.0 / partial_updated_precision + rating.tau_squared)**0.5, rating.activity, rating.tau)
        newrating.player_id = rating.player_id
        newrating
      }
      @teams[1].map!{|rating|
        precision = 1.0 / rating.variance + 1.0 / (n_all*@beta_squared + 2.0 * @gamma_squared + var_team_1 / n_team_1 + var_team_2 / n_team_2 - rating.variance / n_team_2)
        precision_mean = rating.mean / rating.variance + (@scores[1] - @scores[0] + n_team_2 * (mean_team_1 / n_team_1 - mean_team_2 / n_team_2 + rating.mean / n_team_2)) / ( n_all * @beta_squared + 2.0 * @gamma_squared + var_team_1 / n_team_1 + var_team_2/n_team_2 - rating.variance / n_team_2)
        partial_updated_precision = rating.precision + rating.activity*( precision - rating.precision)
        partial_updated_precision_mean =  rating.precision_mean + rating.activity * (precision_mean - rating.precision_mean)
        newrating=Saulabs::TrueSkill::Rating.new(partial_updated_precision_mean / partial_updated_precision, (1.0 / partial_updated_precision + rating.tau_squared)**0.5, rating.activity, rating.tau)
        newrating.player_id = rating.player_id
        newrating
      }
    end
  end
end
