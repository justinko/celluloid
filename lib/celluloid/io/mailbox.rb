require 'thread'

module Celluloid
  module IO
    # An alternative implementation of Celluloid::Mailbox using Wakers
    class Mailbox < Celluloid::Mailbox
      def initialize_signaling
        @waker = Waker.new
      end

      # Add a message to the Mailbox
      def <<(message)
        @lock.synchronize do
          @messages << message
          @waker.signal
        end
        nil
      rescue DeadWakerError
        raise MailboxError, "dead recipient"
      end

      # Add a high-priority system event to the Mailbox
      def system_event(event)
        @lock.synchronize do
          @messages.unshift event

          begin
            @waker.signal
          rescue DeadWakerError
            # Silently fail if messages are sent to dead actors
          end
        end
        nil
      end

      # Receive a message from the Mailbox
      def receive(&block)
        message = nil

        begin
          @waker.wait
          message = next_message(&block)
        end until message

        message
      rescue DeadWakerError
        shutdown # force shutdown of the mailbox
        raise MailboxError, "mailbox shutdown called during receive"
      end

      # Cleanup any IO objects this Mailbox may be using
      def shutdown
        @waker.cleanup
        super
      end
    end
  end
end
