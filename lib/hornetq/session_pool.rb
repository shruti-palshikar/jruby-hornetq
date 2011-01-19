require 'gene_pool'

module HornetQClient
  # Since a Session can only be used by one thread at a time, we could create
  # a Session for every thread. That could result in excessive unused Sessions.
  # An alternative is to create a pool of sessions that can be shared by
  # multiple threads.
  #
  # Each thread can requests a session and then return it once it is no longer
  # needed by that thread. Rather than requesting a session directly using
  # SessionPool::session, it is recommended to pass a block so that the Session
  # is automatically returned to the pool. For example:
  #   session_pool.session do |session|
  #     .. do something with the session here
  #   end
  #
  # Parameters:
  #   see regular session parameters from: HornetQClient::Factory::create_session
  #
  # Additional parameters for controlling the session pool itself
  #   :pool_name         Name of the pool as it shows up in the logger.
  #                      Default: 'HornetQClient::SessionPool'
  #   :pool_size         Maximum Pool Size. Default: 10
  #                      The pool only grows as needed and will never exceed
  #                      :pool_size
  #   :pool_warn_timeout Amount of time to wait before logging a warning when a
  #                      session in the pool is not available. Measured in seconds
  #                      Default: 5.0
  #   :pool_logger       Supply a logger that responds to #debug, #info, #warn and #debug?
  #                      For example: Rails.logger
  #                      Default: None.
  # Example:
  #   session_pool = factory.create_session_pool(config)
  #   session_pool.session do |session|
  #      ....
  #   end
  class SessionPool
    def initialize(factory, parms={})
      # Save Session parms since it will be used every time a new session is
      # created in the pool
      session_parms = parms.dup
      # TODO Use same logger as HornetQ?
      # TODO How to shrink unused connections?
      @pool = GenePool.new(
        :name => parms[:pool_name] || self.class.name,
        :pool_size => parms[:pool_size] || 10,
        :warn_timeout => parms[:pool_warn_timeout] || 5,
        :logger       => parms[:pool_logger]) do
        s = factory.create_session(session_parms)
        # Start the session since it will be used immediately upon creation
        s.start
        puts "Creating Session"
        s
      end

      # Obtain a session from the pool and pass it to the supplied block
      # The session is automatically returned to the pool once the block completes
      def session(&block)
        @pool.with_connection {|s| block.call(s)}
      end

      # Obtain a session from the pool and create a ClientConsumer. 
      # Pass both into the supplied block. 
      # Once the block is complete the consumer is closed and the session is
      # returned to the pool.
      # 
      # See  HornetQClient::ClientConsumer for more information on the consumer
      #      parameters
      #
      # Example
      #   session_pool.consumer('MyQueue') do |session, consumer|
      #     message = consumer.receive(timeout)
      #     puts message.body if message
      #   end
      def consumer(queue_name, &block)
        session do |s|
          consumer = nil
          begin
            consumer = s.create_consumer(queue_name)
            block.call(s, consumer)
          ensure
            consumer.close
          end
        end
      end
      
      # Obtain a session from the pool and create a ClientProducer. 
      # Pass both into the supplied block. 
      # Once the block is complete the consumer is closed and the session is
      # returned to the pool.
      # 
      # See  HornetQClient::ClientProducer for more information on the producer
      #      parameters
      #
      # Example
      #   session_pool.producer('MyAddress') do |session, producer|
      #     message = session.create_message(HornetQClient::Message::TEXT_TYPE,false)
      #     message << "#{Time.now}: ### Hello, World ###"
      #     producer.send(message)
      #   end
      def producer(address, &block)
        session do |s|
          producer = nil
          begin
            producer = s.create_producer(address)
            block.call(s, producer)
          ensure
            producer.close
          end
        end
      end
      
      # Obtain a session from the pool and create a ClientRequestor. 
      # Pass both into the supplied block. 
      # Once the block is complete the requestor is closed and the session is
      # returned to the pool.
      # 
      # See  HornetQClient::ClientRequestor for more information on the requestor
      #
      # Example
      #   session_pool.requestor(parms) do |session, requestor|
      #     ....
      #   end
      def requestor(address, &block)
        session do |s|
          requestor = nil
          begin
            requestor = s.create_requestor(address)
            block.call(s, requestor)
          ensure
            requestor.close
          end
        end
      end
      
      # Obtain a session from the pool and create a ClientServer. 
      # Pass both into the supplied block. 
      # Once the block is complete the requestor is closed and the session is
      # returned to the pool.
      # 
      # See  HornetQClient::ClientServer for more information on the server
      #
      # Example
      #   session_pool.server(queue, timeout) do |session, server|
      #     ....
      #   end
      def server(queue, timeout=0, &block)
        session do |s|
          server = nil
          begin
            server = s.create_server(queue, timeout=0)
            block.call(s, server)
          ensure
            server.close
          end
        end
      end
      
      # Immediately Close all sessions in the pool and release from the pool
      # 
      # TODO: Allow an option to wait for active sessions to be returned before 
      #       closing
      def close
        @pool.each do |s|
          #@pool.remove(s)
          s.close
          #@pool.remove(s)
        end
      end
      
    end
    
  end

end