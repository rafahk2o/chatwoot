# Melck fork: see Messages::VcardContentService.
class Messages::VcardContentJob < ApplicationJob
  queue_as :low

  # The vCard may still be uploading to storage when the job first runs.
  retry_on ActiveStorage::FileNotFoundError, wait: 5.seconds, attempts: 5

  def perform(message)
    Messages::VcardContentService.new(message: message).perform
  end
end
