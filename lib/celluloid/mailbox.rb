require 'thread'

module Celluloid
  class MailboxError < StandardError; end # you can't message the dead

  # Actors communicate with asynchronous messages. Messages are buffered in
  # Mailboxes until Actors can act upon them.
  class Mailbox
    include Enumerable

    def initialize
      @messages = []
      @lock  = Mutex.new
      @dead = false
      initialize_signaling
    end

    def initialize_signaling
      @condition = ConditionVariable.new
    end

    # Add a message to the Mailbox
    def <<(message)
      @lock.synchronize do
        raise MailboxError, "dead recipient" if @dead

        @messages << message
        @condition.signal
      end
      nil
    end

    # Add a high-priority system event to the Mailbox
    def system_event(event)
      @lock.synchronize do
        unless @dead # Silently fail if messages are sent to dead actors
          @messages.unshift event
          @condition.signal
        end
      end
      nil
    end

    # Receive a message from the Mailbox
    def receive(&block)
      message = nil

      @lock.synchronize do
        raise MailboxError, "attempted to receive from a dead mailbox" if @dead

        begin
          message = next_message(&block)
          @condition.wait(@lock) unless message
        end until message
      end

      message
    end

    # Retrieve the next message in the mailbox
    def next_message
      message = nil

      if block_given?
        index = @messages.index do |msg|
          yield(msg) || msg.is_a?(Celluloid::SystemEvent)
        end

        message = @messages.slice!(index, 1).first if index
      else
        message = @messages.shift
      end

      raise message if message.is_a?(Celluloid::SystemEvent)
      message
    end

    # Shut down this mailbox and clean up its contents
    def shutdown
      messages = nil

      @lock.synchronize do
        messages = @messages
        @messages = []
        @dead = true
      end

      messages.each { |msg| msg.cleanup if msg.respond_to? :cleanup }
      true
    end

    # Cast to an array
    def to_a
      @lock.synchronize { @messages.dup }
    end

    # Iterate through the mailbox
    def each(&block)
      to_a.each(&block)
    end

    # Inspect the contents of the Mailbox
    def inspect
      "#<Celluloid::Mailbox:#{object_id} [#{map { |m| m.inspect }.join(', ')}]>"
    end
  end
end
