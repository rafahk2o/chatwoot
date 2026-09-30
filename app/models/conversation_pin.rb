# Melck fork: a conversation pinned by a user to the top of their conversation list.
# Pins are personal; the board keeps its own shared pins in ConversationBoardCard.
class ConversationPin < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :conversation
end
