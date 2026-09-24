# == Schema Information
#
# Table name: conversation_board_cards
#
#  id              :bigint           not null, primary key
#  pinned          :boolean          default(FALSE), not null
#  position        :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  assignee_id     :bigint
#  conversation_id :bigint           not null
#  updated_by_id   :bigint
#
# Indexes
#
#  index_conversation_board_cards_on_account_id       (account_id)
#  index_conversation_board_cards_on_conversation_id  (conversation_id) UNIQUE
#

# Melck fork: pin and manual position of a conversation on the board.
class ConversationBoardCard < ApplicationRecord
  belongs_to :account
  belongs_to :conversation

  # The saved order only applies while the conversation stays in that column.
  def applies_to?(conversation)
    assignee_id == conversation.assignee_id
  end
end
