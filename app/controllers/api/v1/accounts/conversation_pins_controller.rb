# Melck fork: the current user's pinned conversations, identified by display_id.
class Api::V1::Accounts::ConversationPinsController < Api::V1::Accounts::BaseController
  def index
    render json: { payload: pins.joins(:conversation).pluck('conversations.display_id') }
  end

  # POST /conversation_pins { conversation_id }
  def create
    conversation = visible_conversations.find_by!(display_id: params[:conversation_id])
    pins.find_or_create_by!(conversation: conversation)
    head :ok
  end

  # DELETE /conversation_pins/:id - id is the conversation display_id
  def destroy
    pins.where(conversation: Current.account.conversations.where(display_id: params[:id])).delete_all
    head :ok
  end

  private

  def pins
    ConversationPin.where(account_id: Current.account.id, user_id: Current.user.id)
  end

  def visible_conversations
    Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account).perform
  end
end
