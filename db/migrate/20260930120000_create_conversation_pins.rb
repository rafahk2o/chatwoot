# Melck fork: conversations each user pins to the top of their conversation list.
class CreateConversationPins < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_pins do |t|
      t.references :account, null: false, index: true
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :conversation_pins, [:user_id, :conversation_id], unique: true
  end
end
