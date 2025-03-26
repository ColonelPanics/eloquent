require "rails_helper"

describe PlayerGamesController, :type => :controller do
  describe "show" do
    it "renders successfully with the player and the game" do
      game = FactoryBot.create(:game)
      player = FactoryBot.create(:player)

      get :show, params: {player_id: player, id: game}
      expect(response).to have_http_status(:success)

      expect(assigns(:game)).to eq game
      expect(assigns(:player)).to eq player
    end
  end
end
