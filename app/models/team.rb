class Team < ApplicationRecord
  FIRST_PLACE_RANK = 1

  has_many :memberships, dependent: :destroy
  has_many :players, through: :memberships
  belongs_to :result, optional: true

  validates :rank, numericality: { only_integer: true, greater_than_or_equal_to: FIRST_PLACE_RANK }
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :winners, -> {
    where(:rank => FIRST_PLACE_RANK)
  }

  scope :losers, -> {
    where.not(:rank => FIRST_PLACE_RANK)
  }
end
