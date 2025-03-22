FactoryBot.define do
  factory :team do
    players { [FactoryBot.build(:player)] }
    rank { 1 }

    score { rand(0..10) }
  end
end
