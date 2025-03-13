class Team < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :players, through: :memberships
  belongs_to :result, optional: true

  scope :winners, -> {
    where(:winner => true)
  }

  scope :losers, -> {
    where(:winner => false) { |loser| !loser.result.tie? }
  }
end
