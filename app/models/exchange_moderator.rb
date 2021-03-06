# frozen_string_literal: true

class ExchangeModerator < ApplicationRecord
  belongs_to :exchange
  belongs_to :user
  validates :user_id, presence: true, uniqueness: { scope: :exchange_id }
  validates :exchange_id, presence: true
end
