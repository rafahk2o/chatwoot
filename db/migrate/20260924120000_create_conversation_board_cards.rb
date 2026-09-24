# Melck fork: manual order and pinning of cards on the conversation board.
# Kept apart from conversations so reordering never fires conversation webhooks.
class CreateConversationBoardCards < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_board_cards do |t|
      t.references :account, null: false, index: true
      t.references :conversation, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      # Column the order was set in; ignored once the conversation is reassigned.
      t.bigint :assignee_id
      t.boolean :pinned, null: false, default: false
      t.integer :position
      t.bigint :updated_by_id
      t.timestamps
    end
  end
end
