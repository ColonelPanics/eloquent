require 'rails_helper'

RSpec.describe Team, type: :model do
  describe "validations" do

    subject {
      Team.new(
        rank: 1,
        score: 6
      )
    }

    context "with valid attributes" do
      it { is_expected.to be_valid }
    end

    describe "rank" do
      it "cannot be negative" do
        subject.rank = -1
        expect(subject).to have_error(:rank, :greater_than_or_equal_to)
      end
      it "cannot be zero" do
        subject.rank = 0
        expect(subject).to have_error(:rank, :greater_than_or_equal_to)
      end
      it "cannot be nil" do
        subject.rank = nil
        expect(subject).to have_error(:rank, :not_a_number)
      end
    end

    describe "score" do
      it "cannot be negative" do
        subject.score = -1
        expect(subject).to have_error(:score, :greater_than_or_equal_to)
      end
      it "can be zero" do
        subject.score = 0
        expect(subject).to be_valid
      end
      it "cannot be nil" do
        subject.score = nil
        expect(subject).to have_error(:score, :not_a_number)
      end
    end
  end
end
