class Player < ApplicationRecord
  has_many :ratings, dependent: :destroy do
    def find_or_create(game)
      where(game_id: game.id).first || create({game: game, pro: false}.merge(game.rater.default_attributes))
    end
  end

  has_many :memberships
  has_many :teams, through: :memberships

  has_many :results, through: :teams do
    def against(opponent)
      joins("INNER JOIN teams AS other_teams ON results.id = other_teams.result_id")
        .where("other_teams.id != teams.id")
        .joins("INNER JOIN memberships AS other_players_teams ON other_teams.id = other_players_teams.team_id")
        .where("other_players_teams.player_id = ?", opponent)
    end
  end

  before_destroy do
    results.each { |result| result.destroy }
  end

  validates :name, uniqueness: true, presence: true
  validates :email, allow_blank: true, format: { with: /@/, message: "expected an @ character" }

  def recent_results
    results.order("results.created_at DESC").limit(5)
  end

  def rewind_rating!(game)
    rating = ratings.where(game_id: game.id).first
    rating.rewind!
  end

  def total_ties(game)
    results.where(game_id: game).to_a.count { |r| r.tie? }
  end

  def ties(game, opponent)
    results.where(game_id: game).against(opponent).to_a.count { |r| r.tie? }
  end

  def total_wins(game)
    results.where(game_id: game, teams: { winner: true }).to_a.count { |r| !r.tie? }
  end

  def total_wins_on_for(game)
    # Number of wins on the "For" side
    results.where(game_id: game, teams: { winner: true }).to_a.count { |r| r.side == 'for' }
  end

  def total_wins_on_against(game)
    # Number of wins on the "Against" side
    results.where(game_id: game, teams: { winner: true }).to_a.count { |r| r.side == 'against' }
  end

  def wins(game, opponent)
    results.where(game_id: game, teams: { winner: true }).against(opponent).to_a.count { |r| !r.tie? }
  end

  def total_losses(game)
    results.where(game_id: game, teams: { winner: false }).to_a.count { |r| !r.tie? }
  end

  def losses(game, opponent)
    results.where(game_id: game, teams: { winner: false }).against(opponent).to_a.count { |r| !r.tie? }
  end

  def get_all_streaks(game)
    streaks = []
    currentStreak = Streak.new()
    currentStreakUnbeaten = Streak.new()
    currentStreakUnbeaten.unbeaten = true

    results = self.results.where(game_id: game).order("created_at ASC")

    for result in results
      # Identify whether this match was a win, loss or draw
      won_game = result.winners.include?(self) && !result.tie?
      lost_game = !result.winners.include?(self) && !result.tie?
      tie_game = result.tie?

      # Continue win streak if we're on one
      if (won_game and currentStreak.win)
        # Add to win streak
        currentStreak.resultTimes.append(result.created_at)
        # Add to current unbeaten streak
        currentStreakUnbeaten.resultTimes.append(result.created_at)
      # Continue loss streak if we're on one
      elsif (lost_game and not currentStreak.win)
        # Add to loss streak
        currentStreak.resultTimes.append(result.created_at)
      # Add to unbeaten run if we're on one
      elsif tie_game #and currentStreak.win 
        # Add to current unbeaten streak
        currentStreakUnbeaten.resultTimes.append(result.created_at)
      end

      # Ending the streak if:
      # - Player won when on a losing streak
      # - Player lost when on a winning streak
      # - Player draws
      if (won_game and not currentStreak.win) or (lost_game and currentStreak.win) or tie_game 
        puts "Streak over: #{tie_game && 'tie' || (won_game && 'win' || 'lose')} during a #{currentStreak.win && 'win' || 'lose'} streak"
        # end of streak
        if currentStreak.count >= 1
          # Streak over and more than 1 match so adding to past streaks
          streaks.append(currentStreak)
        end
        # Start new streak
        currentStreak = Streak.new()
        if lost_game
          # Save and reset unbeaten streak
          if currentStreakUnbeaten.count >= 1
            streaks.append(currentStreakUnbeaten)
          end
          currentStreakUnbeaten = Streak.new()
          currentStreakUnbeaten.unbeaten = true
        end
        if won_game or lost_game
          # Starting new #{ won_game && 'win' || 'lose'} streak
          currentStreak.resultTimes.append(result.created_at)
        end
        currentStreak.win = won_game
      end
    end
    # Return the unbeaten run if last result was a tie
    if currentStreak.win and currentStreakUnbeaten.count > currentStreak.count
      return {'past': streaks, 'current': currentStreakUnbeaten}
    else
      return {'past': streaks, 'current': currentStreak}
    end
  end

  def get_streaks(game)
    streaks = get_all_streaks(game)
    winStreaks = streaks[:past].select {|s| s.win && !s.unbeaten }.sort_by {|s| s.resultTimes.size }.reverse
    loseStreaks = streaks[:past].select {|s| !s.win }.sort_by {|s| s.resultTimes.size }.reverse
    unbeatenStreaks = streaks[:past].select {|s| s.win && s.unbeaten }.sort_by {|s| s.resultTimes.size }.reverse
    currentStreakType = streaks[:current].unbeaten && "unbeaten" || (streaks[:current].win &&  "win(s)" || "loss(es)")
    return {
      'win': winStreaks.size > 0 && winStreaks[0] || Streak.new(),
      'lose': loseStreaks.size > 0 && loseStreaks[0] || Streak.new(),
      'unbeaten': unbeatenStreaks.size > 0 && unbeatenStreaks[0] || Streak.new(),
      'current': streaks[:current],
      'currentType': currentStreakType
    }
  end

  def win_streak(game)
    all = get_all_streaks(game)
    all_win = streaks[:past].select {|s| s.win && !s.unbeaten }.sort_by {|s| s.resultTimes.size }.reverse
    win = all_win.size > 0 && winStreaks[0] || Streak.new()

    count = win.count

    return {
      'count': count,
      'duration': duration
    }
  end

end

class Streak
  attr_accessor :win
  attr_accessor :unbeaten
  attr_accessor :resultTimes

  def initialize
    @win = true
    @unbeaten = false
    @resultTimes = []
  end

  def count
    return @resultTimes.size
  end

  def fromDate
    return count > 0 && @resultTimes[0] || 0
  end

  def toDate
    return count > 0 && @resultTimes[-1] || 0
  end
end
