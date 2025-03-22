FactoryBot.define do
  factory :player do
    name { Faker::Name.unique.name }
    email { Faker::Internet.email }
  end
end
