class Result < ApplicationRecord
  has_many :teams
  belongs_to :game, touch: true

  validates :for, presence: true, numericality: { only_integer: true }
  validates :against, presence: true, numericality: { only_integer: true }
  validates :game, presence: true
  scope :most_recent_first, -> { order created_at: :desc }
  scope :for_game, -> (game) { where(game_id: game.id) }

  validate do |result|
    if result.winners.empty?
      result.errors.add(:teams, "must have a winner")
    end

    if result.players.size != players.uniq.size
      result.errors.add(:teams, "must have unique players")
    end

    if result.teams.size < result.game.min_number_of_teams
      result.errors.add(:teams, "must have at least #{result.game.min_number_of_teams} teams")
    end

    if result.game.max_number_of_teams && result.teams.size > result.game.max_number_of_teams
      result.errors.add(:teams, "must have at most #{result.game.max_number_of_teams} teams")
    end

    if result.teams.any?{|team| team.players.size < result.game.min_number_of_players_per_team}
      result.errors.add(:teams, "must have at least #{result.game.min_number_of_players_per_team} players per team")
    end

    if result.game.max_number_of_players_per_team && result.teams.any?{|team| team.players.size > result.game.max_number_of_players_per_team}
      result.errors.add(:teams, "must have at most #{result.game.max_number_of_players_per_team} players per team")
    end

    if !result.game.allow_ties && result.teams.map(&:rank).uniq.size != result.teams.size
      result.errors.add(:teams, "game does not allow ties")
    end
  end

  def players
    teams.map(&:players).flatten
  end

  def winners
    teams.select{ |team| team.rank == Team::FIRST_PLACE_RANK }.map(&:players).flatten
  end

  def losers
    teams.select{ |team| team.rank != Team::FIRST_PLACE_RANK }.map(&:players).flatten
  end

  def tie?
    teams.count == teams.winners.count
  end

  def as_json(options = {})
    {
      winner: winners.first.name,
      loser: losers.first.name,
      created_at: created_at.utc.to_s
    }
  end

  def most_recent?
    teams.all? do |team|
      team.players.all? do |player|
        player.results.where(game_id: game.id).order("created_at DESC").first == self
      end
    end
  end

  def skill_swing(player)
    # Calculate how the rating changed for player by comparing the skill rating
    # in this match to the one from previous
    
    # The RatingHistoryEvent is created before the result, check for one created a second before the result
    this_skill = RatingHistoryEvent.includes(:rating).where(:created_at => (self.created_at - 1.seconds)..self.created_at, ratings: { player_id: player, game_id: self.game_id }).first.value

    # Get the player's last 2 results and take the first one from the list as that will be oldest
    prev_result = player.results.where(game_id: self.game_id).last(2).first
    # If the previous result is the same then this is their first match of 'game' so use default value for whatever rater system this game uses
    if prev_result.id == self.id
      prev_skill = Game.find(self.game_id).rater.default_attributes[:value]
    else
      # The RatingHistoryEvent is created before the result, check for one created a second before the result
      prev_skill = RatingHistoryEvent.includes(:rating).where(:created_at => (prev_result.created_at - 1.seconds)..prev_result.created_at, ratings: { player_id: player, game_id: prev_result.game_id }).first.value  
    end
    return (this_skill - prev_skill)
  end

end
