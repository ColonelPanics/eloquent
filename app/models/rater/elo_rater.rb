# frozen_string_literal: true

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
      raise ArgumentError, "passed `result` that was not a Result model" unless result.is_a?(Result)

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
end
