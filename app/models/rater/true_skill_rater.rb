# frozen_string_literal: true

module Rater
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
      raise ArgumentError, "passed `result` that was not a Result model" unless result.is_a?(Result)

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
