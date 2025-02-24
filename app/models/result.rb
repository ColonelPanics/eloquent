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

    if !result.game.allow_ties && result.tie?
      result.errors.add(:teams, "game does not allow ties")
    end
  end

  def players
    teams.map(&:players).flatten
  end

  def verdict
    # Check for a score draw
    if self.against == self.for
      # They drew, select all players involved
      winteam = ''
      loseteam = ''
      winners = teams.find_all.map(&:players).flatten
      winscore = self.for
      losescore = self.against
      losers = []
      tie = true
      side = 'tie'
    else
      # If 'For' side won
      if self.for > self.against 
        winteam = teams.first
        winscore = self.for
        loseteam = teams.last
        losescore = self.against
        side = 'for'
      # If 'Against' side won
      elsif self.against > self.for
        winteam = teams.last
        winscore = self.against
        loseteam = teams.first
        losescore = self.for
        side = 'against'
      end
      tie = false
      winners = winteam.players
      losers = loseteam.players
    end
    return winners, losers, tie, winscore, losescore, side, winteam, loseteam
  end

  def winners
    # Returns an array of Player objects that won the match
    # Note: In a draw, everyone is a winner!
    verdict[0]
  end

  def losers
    # Returns an array of Player objects that lost the match 
    verdict[1]
  end

  def tie?
    # Boolean to check if match is a tie
    verdict[2]
  end

  def winscore
    # A way to access the score of the winner so later things don't 
    # need to decide whether for or against score were the winners
    verdict[3].to_f
  end

  def losescore
    # A way to access the score of the loser so later things don't 
    # need to decide whether for or against score were the losers
    verdict[4].to_f
  end

  def side
    # For seeing if the for or against side won
    # Useful for eventual implementation of home/away based stats
    verdict[5]
  end

  def winteam
    # The Team object for the team that won
    verdict[6]
  end

  def loseteam
    # The Team object for the team that lost
    verdict[7]
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

    # Get the player's results before this result and take the first one of the last 2 from this list as it'll be the previous match played
    # by this player in this game
    prev_result = player.results.where(game_id: self.game_id, :created_at => 100.years.ago..self.created_at).last(2).first
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
