require "rails_helper"

describe ApplicationHelper, :type => :helper do
  describe "gravatar" do
    it "uses a hash from player name if the player doesn't have an email address" do
      player = FactoryBot.build(:player, name: "claudia", email: "")

      helper.gravatar_url(player).should == "https://robohash.org/2b9ff3efc4a999ecfacd18c4bbc57a2e?size=32x32"
    end

    it "uses the player's gravatar url if he/she has an email address" do
      player = FactoryBot.build(:player, email: "test@example.com")

      helper.gravatar_url(player).should == "https://robohash.org/55502f40dc8b7c769880b10874abc9d0?gravatar=hashed&size=32x32"
    end

    it "can take a custom size" do
      player = FactoryBot.build(:player, email: "test@example.com")

      helper.gravatar_url(player, size: 64).should == "https://robohash.org/55502f40dc8b7c769880b10874abc9d0?gravatar=hashed&size=64x64"
    end
  end
end
