-module(rtmpmsg_chunk_decode_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../include/internal/rtmpmsg_internal.hrl").

chunk_size_test_() ->
    [
     {"チャンクサイズの初期値が適切か",
      fun () ->
              Dec = rtmpmsg_chunk_decode:init(),
              ?assertMatch(?CHUNK_SIZE_DEFAULT, rtmpmsg_chunk_decode:get_chunk_size(Dec))
      end},
     {"チャンクサイズの変更",
      fun () ->
              Dec0 = rtmpmsg_chunk_decode:init(),

              NewChunkSize = 12345,
              Dec1 = rtmpmsg_chunk_decode:set_chunk_size(Dec0, NewChunkSize),

              ?assertMatch(NewChunkSize, rtmpmsg_chunk_decode:get_chunk_size(Dec1))
      end}
    ].

decode_test_() ->
    [
     {"基本的なチャンクデータのデコードができる",
      fun () ->
              InputChunk = input_chunk(),
              assert_decode_chunks([InputChunk])
      end},
     {"連続したチャンクデータのデコードができる: fmt0 => fmt1",
      fun () ->
              InputChunk0 = input_chunk(),
              InputChunk1 = InputChunk0#chunk{msg_type_id = 200},
              assert_decode_chunks([InputChunk0, InputChunk1])
      end},
     {"連続したチャンクデータのデコードができる: fmt0 => fmt2",
      fun () ->
              InputChunk0 = input_chunk(),
              InputChunk1 = InputChunk0#chunk{timestamp = 6789},
              assert_decode_chunks([InputChunk0, InputChunk1])
      end},
     {"連続したチャンクデータのデコードができる: fmt0 => fmt3",
      fun () ->
              InputChunk = input_chunk(),
              assert_decode_chunks([InputChunk, InputChunk])
      end},
     {"連続したチャンクデータのデコードができる: fmt0 => fmt1 => fmt2 => fmt3",
      fun () ->
              InputChunk0 = input_chunk(),
              InputChunk1 = InputChunk0#chunk{msg_type_id = 200},
              InputChunk2 = InputChunk1#chunk{timestamp = 6789},
              InputChunk3 = InputChunk2,
              assert_decode_chunks([InputChunk0, InputChunk1, InputChunk2, InputChunk3])
      end},
     {"連続したチャンクデータのデコードができる: fmt0 => fmt2 => fmt0 => fmt1",
      fun () ->
              InputChunk0 = input_chunk(),
              InputChunk1 = InputChunk0#chunk{timestamp = 6789},
              InputChunk2 = InputChunk1#chunk{timestamp = 1000},
              InputChunk3 = InputChunk2#chunk{payload = <<"a">>},
              assert_decode_chunks([InputChunk0, InputChunk1, InputChunk2, InputChunk3])
      end},
     {"最初のチャンクフォーマットが 0 以外の場合は、エラーになる",
      fun () ->
              InputChunk0 = input_chunk(),
              InputChunk1 = InputChunk0#chunk{msg_type_id = 200},

              %% 最初のチャンク(fmt0)を取り除く
              {_, TmpBin} = encode_chunks([InputChunk0, InputChunk1]),
              {_, _, InputBin} = rtmpmsg_chunk_decode:decode(rtmpmsg_chunk_decode:init(), TmpBin),

              Dec = rtmpmsg_chunk_decode:init(),
              ?assertError({first_chunk_format_id_must_be_0, _, _}, rtmpmsg_chunk_decode:decode(Dec, InputBin))
      end},
     {"ChunkBasicHeaderが 2バイト のチャンク",
      fun () ->
              InputChunk = (input_chunk())#chunk{id = 70},
              assert_decode_chunks([InputChunk])
      end},
     {"ChunkBasicHeaderが 3バイト のチャンク",
      fun () ->
              InputChunk = (input_chunk())#chunk{id = 700},
              assert_decode_chunks([InputChunk])
      end},
     {"ペイロードが複数のチャンクにまたがる場合: チャンクサイズの倍数",
      fun () ->
              InputChunk = (input_chunk())#chunk{payload = crypto:rand_bytes(?CHUNK_SIZE_DEFAULT * 3)},
              assert_decode_chunks([InputChunk])
      end},
     {"ペイロードが複数のチャンクにまたがる場合",
      fun () ->
              InputChunk = (input_chunk())#chunk{payload = crypto:rand_bytes(round(?CHUNK_SIZE_DEFAULT * 2.5))},
              assert_decode_chunks([InputChunk])
      end},
     {"チャンクが細切れになっている場合",
      fun () ->
              Dec0 = rtmpmsg_chunk_decode:init(),

              InputChunk0 = input_chunk(),
              InputChunk1 = InputChunk0#chunk{msg_type_id = 200},
              InputChunk2 = InputChunk1#chunk{timestamp = 6789},
              InputChunk3 = InputChunk2,
              InputChunks = [InputChunk0, InputChunk1, InputChunk2, InputChunk3],
              {_, InputBin0} = encode_chunks(InputChunks),

              SentinelByte = 0,
              Result = 
                  lists:foldl(fun (Byte, {AccDec, AccBin, Count}) ->
                                      case rtmpmsg_chunk_decode:decode(AccDec, AccBin) of
                                          {partial, AccDec1, AccBin1} ->
                                              {AccDec1, <<AccBin1/binary, Byte>>, Count};
                                          {Chunk, AccDec1, AccBin1} ->
                                              ?assertEqual(lists:nth(Count+1, InputChunks), Chunk),
                                              {AccDec1, <<AccBin1/binary, Byte>>, Count+1}
                                      end
                              end,
                              {Dec0, <<"">>, 0},
                              binary_to_list(InputBin0) ++ [SentinelByte]),

              Len = length(InputChunks),
              ?assertMatch({_, <<SentinelByte>>, Len}, Result)
      end},
     {"チャンクサイズが途中で変わる",
      fun () ->
              InputChunk0 = (input_chunk())#chunk{payload = crypto:rand_bytes(?CHUNK_SIZE_DEFAULT * 3)},
              InputChunk1 = InputChunk0#chunk{msg_type_id = 200},
              InputChunk2 = InputChunk1#chunk{timestamp = 6789},
              InputChunk3 = InputChunk2,

              {Enc0, InputBin0} = encode_chunks([InputChunk0, InputChunk1]),
              Enc1 = rtmpmsg_chunk_encode:set_chunk_size(Enc0, ?CHUNK_SIZE_DEFAULT * 2),
              {_, InputBin1} = encode_chunks(Enc1, [InputChunk2, InputChunk3]),

              Dec0 = assert_decode_chunks(InputBin0, [InputChunk0, InputChunk1]),
              Dec1 = rtmpmsg_chunk_decode:set_chunk_size(Dec0, ?CHUNK_SIZE_DEFAULT * 2),
              assert_decode_chunks(Dec1, InputBin1, [InputChunk2, InputChunk3])
      end},
     {"拡張タイムスタンプフィールドが存在する",
      fun () ->
              %% 境界値
              InputChunk0 = (input_chunk())#chunk{timestamp = 16#FFFFFF},
              assert_decode_chunks([InputChunk0]),

              InputChunk1 = (input_chunk())#chunk{timestamp = 16#12345678},
              assert_decode_chunks([InputChunk1]),
              assert_decode_chunks([InputChunk1, InputChunk1]) % fmt1 => fmt3
      end},
     {"拡張タイムスタンプフィールドが存在する: delta",
      fun () ->
              %% 境界値
              InputChunk0 = (input_chunk())#chunk{timestamp = 10},
              InputChunk1_a = InputChunk0#chunk{timestamp = 10 + 16#FFFFFF},
              assert_decode_chunks([InputChunk0, InputChunk1_a]),

              %% fmt1
              InputChunk1_b = InputChunk0#chunk{timestamp = 10 + 16#12345678, msg_type_id=200},
              assert_decode_chunks([InputChunk0, InputChunk1_b]),

              %% fmt2
              InputChunk1_c = InputChunk0#chunk{timestamp = 10 + 16#12345678},
              assert_decode_chunks([InputChunk0, InputChunk1_c])
      end},
     {"複数のチャンクストリームID",
      fun () ->
              InputChunk0 = input_chunk(),
              InputChunk1 = (InputChunk0)#chunk{id = 10},
              InputChunk2 = (InputChunk0)#chunk{id = 100},

              assert_decode_chunks([InputChunk0, InputChunk1, InputChunk2])
      end},
     {"複数のチャンクストリームIDが混在している",
      fun () ->
              InputChunk0 = (input_chunk())#chunk{payload = crypto:rand_bytes(?CHUNK_SIZE_DEFAULT * 3)},
              InputChunk1 = (InputChunk0)#chunk{id = 10},
              InputChunk2 = (InputChunk0)#chunk{id = 100},

              {_, InputBin0} = encode_chunks([InputChunk0]),
              {_, InputBin1} = encode_chunks([InputChunk1]),
              {_, InputBin2} = encode_chunks([InputChunk2]),

              InterleavedBin = 
                  list_to_binary(
                    lists:zipwith3(fun (Bin0, Bin1, Bin2) -> [Bin0, Bin1, Bin2] end,
                                   split_chunk_bytes(InputBin0, 1, 11, ?CHUNK_SIZE_DEFAULT),
                                   split_chunk_bytes(InputBin1, 1, 11, ?CHUNK_SIZE_DEFAULT),
                                   split_chunk_bytes(InputBin2, 2, 11, ?CHUNK_SIZE_DEFAULT))),

              assert_decode_chunks(InterleavedBin, [InputChunk0, InputChunk1, InputChunk2])
      end},
     {"複数のチャンクストリームIDが混在していて かつ 細切れになっている",
      fun () ->
              InputChunk0 = (input_chunk())#chunk{payload = crypto:rand_bytes(?CHUNK_SIZE_DEFAULT * 3)},
              InputChunk1 = (InputChunk0)#chunk{id = 10},
              InputChunk2 = (InputChunk0)#chunk{id = 100},
              InputChunks = [InputChunk0, InputChunk1, InputChunk2],

              {_, InputBin0} = encode_chunks([InputChunk0]),
              {_, InputBin1} = encode_chunks([InputChunk1]),
              {_, InputBin2} = encode_chunks([InputChunk2]),

              InterleavedBin = 
                  list_to_binary(
                    lists:zipwith3(fun (Bin0, Bin1, Bin2) -> [Bin0, Bin1, Bin2] end,
                                   split_chunk_bytes(InputBin0, 1, 11, ?CHUNK_SIZE_DEFAULT),
                                   split_chunk_bytes(InputBin1, 1, 11, ?CHUNK_SIZE_DEFAULT),
                                   split_chunk_bytes(InputBin2, 2, 11, ?CHUNK_SIZE_DEFAULT))),

              SentinelByte = 0,
              Result = 
                  lists:foldl(fun (Byte, {AccDec, AccBin, Count}) ->
                                      case rtmpmsg_chunk_decode:decode(AccDec, AccBin) of
                                          {partial, AccDec1, AccBin1} ->
                                              {AccDec1, <<AccBin1/binary, Byte>>, Count};
                                          {Chunk, AccDec1, AccBin1} ->
                                              ?assertEqual(lists:nth(Count+1, InputChunks), Chunk),
                                              {AccDec1, <<AccBin1/binary, Byte>>, Count+1}
                                      end
                              end,
                              {rtmpmsg_chunk_decode:init(), <<"">>, 0},
                              binary_to_list(InterleavedBin) ++ [SentinelByte]),

              Len = length(InputChunks),
              ?assertMatch({_, <<SentinelByte>>, Len}, Result)
      end}
    ].

input_chunk() ->
    #chunk{id            = 4,
           msg_stream_id = 2,
           msg_type_id   = 3,
           timestamp     = 4567,
           payload       = <<"abcde">>}.

assert_decode_chunks(InputChunks) ->
    {_, InitBin} = encode_chunks(InputChunks),
    assert_decode_chunks(InitBin, InputChunks).

assert_decode_chunks(InitBin, InputChunks) ->
    InitDec = rtmpmsg_chunk_decode:init(),
    assert_decode_chunks(InitDec, InitBin, InputChunks).

assert_decode_chunks(InitDec, InitBin, InputChunks) ->
    {LastDec, UnconsumedBin} =
        lists:foldl(fun (InputChunk, {AccDec, AccBin}) ->
                            {Chunk, Dec, Rest} = rtmpmsg_chunk_decode:decode(AccDec, AccBin),
                            ?assertEqual(InputChunk, Chunk),
                            {Dec, Rest}
                    end,
                    {InitDec, InitBin},
                    InputChunks),
    ?assertEqual(<<"">>, UnconsumedBin),
    LastDec.

encode_chunks(Chunks) ->
    encode_chunks(rtmpmsg_chunk_encode:init(), Chunks).

encode_chunks(InitEnc, Chunks) ->
    {LastEnc, EncodedData} =
        lists:foldl(fun (Chunk, {AccEnc, AccBin}) ->
                            {Enc, Bin} = rtmpmsg_chunk_encode:encode(AccEnc, Chunk),
                            {Enc, AccBin ++ Bin}
                    end,
                    {InitEnc, []},
                    Chunks),
    {LastEnc, list_to_binary(EncodedData)}.

split_chunk_bytes(<<"">>, _, _, _) ->
    [];
split_chunk_bytes(Bytes, BasicHeaderSize, MessageHeaderSize, ChunkSize) ->
    PerChunkSize = BasicHeaderSize+MessageHeaderSize+ChunkSize,
    <<PerChunkBytes:PerChunkSize/binary, Rest/binary>> = Bytes,
    [PerChunkBytes | split_chunk_bytes(Rest, BasicHeaderSize, 0, ChunkSize)].