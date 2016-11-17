%% coding: latin-1
-module(rtmpmsg_message_decode_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../include/rtmpmsg.hrl").
-include("../include/internal/rtmpmsg_internal.hrl").

%% NOTE: encodeのテストも兼ねてしまっている

decode_test_() ->
    [
     {"set_chunk_sizeメッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:set_chunk_size(1234))
      end},
     {"abortメッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:abort(10))
      end},
     {"ackメッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:ack(56789))
      end},
     {"win_ack_sizeメッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:win_ack_size(45678))
      end},
     {"set_peer_bandwidthメッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:set_peer_bandwidth(4567, soft))
      end},
     {"user_controlメッセージのstream_beginイベントのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:event_stream_begin(10))
      end},
     {"user_controlメッセージのstream_eofイベントのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:event_stream_eof(10))
      end},
     {"user_controlメッセージのstream_dryイベントのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:event_stream_dry(10))
      end},
     {"user_controlメッセージのset_buffer_lengthイベントのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:event_set_buffer_length(10, 1234))
      end},
     {"user_controlメッセージのstream_is_recordedイベントのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:event_stream_is_recorded(10))
      end},
     {"user_controlメッセージのping_requestイベントのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:event_ping_request(3456))
      end},
     {"user_controlメッセージのping_responseイベントのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:event_ping_response(3456))
      end},
     {"user_controlメッセージのbuffer_emptyイベントのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:event_buffer_empty(10))
      end},
     {"user_controlメッセージのbuffer_readyイベントのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:event_buffer_ready(10))
      end},
     {"user_controlメッセージの未知のイベントのデコード",
      fun () ->
              UnknownEvent = #rtmpmsg_event_unknown{type_id=10, payload = <<"xyzzy">>},
              assert_message_decode(rtmpmsg:message(10, 0, #rtmpmsg_user_control{event = UnknownEvent}))
      end},
     {"audioメッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:audio(10, 1234, <<"dummy_audio_data">>))
      end},
     {"videoメッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:video(10, 1234, <<"dummy_video_data">>))
      end},
     {"command(AMF0)メッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:command(10, amf0, <<"connect">>, 0.0,
                                                    amf:object([{<<"a">>, <<"b">>}]),
                                                    [<<"string">>, [1.0, 2.0, 3.0]]))
      end},
     {"command(AMF3)メッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:command(10, amf3, <<"connect">>, 0.0,
                                                    amf:object([{<<"a">>, <<"b">>}]),
                                                    [<<"string">>, [1.0, 2.0, 3.0]]))
      end},
     {"data(AMF0)メッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:data(10, amf0,
                                                 [amf:object([{<<"a">>, <<"b">>},
                                                              {<<"c">>, 10.4}])]))
      end},
     {"data(AMF3)メッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:data(10, amf3,
                                                 [amf:object([{<<"a">>, <<"b">>},
                                                              {<<"c">>, 10.4}])]))
      end},
     {"aggregateメッセージのデコード",
      fun () ->
              Msg1 = rtmpmsg:ack(56789),
              Msg2 = rtmpmsg:command(10, amf0, <<"connect">>, 0.0, amf:object([{<<"a">>, <<"b">>}]), []),
              Msg3 = rtmpmsg:event_buffer_ready(10),
              assert_message_decode(rtmpmsg:aggregate(10, [Msg1,Msg2,Msg3]))
      end},
     {"shared_object(AMF0)メッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:shared_object(10, amf0, <<"payload">>))
      end},
     {"shared_object(AMF3)メッセージのデコード",
      fun () ->
              assert_message_decode(rtmpmsg:shared_object(10, amf3, <<"payload">>))
      end},
     {"未知のメッセージのデコード",
      fun () ->
              Msg = #rtmpmsg_unknown{type_id = 111, payload = <<"payload">>},
              assert_message_decode(rtmpmsg:message(10, 1234, Msg))
      end}
    ].

decode_invalid_data_test_() ->
    [
     {"commandの不正なデータのデコード",
      fun () ->
              Chunk = make_chunk_data(10, 1234, ?TYPE_COMMAND_AMF0, <<"">>),
              Msg = rtmpmsg_message_decode:decode_chunk(Chunk),

              ExpectMsg = #rtmpmsg_unknown{type_id = ?TYPE_COMMAND_AMF0, payload = <<"">>},
              ?assertEqual(rtmpmsg:message(10, 1234, ExpectMsg), Msg)
      end}
    ].

assert_message_decode(InputMsg) ->
    ChunkStreamId = 3,
    InputChunk = rtmpmsg_message_encode:encode_to_chunk(ChunkStreamId, InputMsg),
    Msg = rtmpmsg_message_decode:decode_chunk(InputChunk),
    ?assertEqual(InputMsg, Msg).

make_chunk_data(StreamId, Timestamp, MsgTypeId, Payload) ->
    ChunkStreamId = 3,
    #chunk{
       id            = ChunkStreamId,
       timestamp     = Timestamp,
       msg_type_id   = MsgTypeId,
       msg_stream_id = StreamId,
       payload       = Payload
      }.
