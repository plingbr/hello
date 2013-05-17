-module(jsonrpc_2_compliance_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").

-include("../include/hello2.hrl").
-include_lib("yang/include/typespec.hrl").
-include("hello2_test_jsonrpc_compliance.hrl").

-define(REQ_ID, 1).

-define(equal(Expected, Actual),
    (fun (Expected@@@, Expected@@@) -> true;
         (Expected@@@, Actual@@@) ->
             ct:fail("MISMATCH(~s:~b, ~s)~nExpected: ~p~nActual:   ~p~n",
		     [?FILE, ?LINE, ??Actual, Expected@@@, Actual@@@])
     end)(Expected, Actual)).

-define(match(Guard, Expr),
        ((fun () ->
                  case (Expr) of
                      Guard -> ok;
                      V -> ct:fail("MISMATCH(~s:~b, ~s)~nExpected: ~p~nActual:   ~p~n",
                                   [?FILE, ?LINE, ??Expr, ??Guard, V])
                  end
          end)())).

%% ---------------------------------------------------------------------
%% -- test cases
error_codes(_Config) ->
    ErrorCode = fun (Code, Req) -> Code = field(request(Req), "error.code") end,

    %% parse error
    ErrorCode(-32700, "{aa"),
    ErrorCode(-32700, "\"b"),
    ErrorCode(-32700, "[fb]"),
    ErrorCode(-32700, "{method: null, params: null}"),

    %% invalid request
    ErrorCode(-32600, "\"foo\""),
    ErrorCode(-32600, "[]"),
    ErrorCode(-32603, "{\"method\": null, \"params\": [], \"id\": 1}"),
    ErrorCode(-32600, "{\"method\": \"foobar\", \"params\": 0, \"id\": 1}"),

    %% method not found
    ErrorCode(-32601, {"does_not_exist", []}),

    %% invalid parameters
    ErrorCode(-32602, {"subtract", [<<"a">>, <<"b">>]}), % invalid types
    ErrorCode(-32602, {"subtract", [1]}). % required parameter is missing

param_structures(_Config) ->
    %% by-position
    Req1 = request({"subtract", [2,1]}),
    ?equal(1, field(Req1, "result")),

    %% by-name
    Req2 = request({"subtract", {[{"subtrahend", 2}, {"minuend", 1}]}}),
    ?equal(1, field(Req2, "result")),

    %% by-name reversed order
    Req3 = request({"subtract", {[{"minuend", 1}, {"subtrahend", 2}]}}),
    ?equal(1, field(Req3, "result")),
    ok.

response_fields(_Config) ->
    %% success case
    Req1 = {Props1} = request({"subtract", [2,1]}),
    1         = field(Req1, "result"),
    <<"2.0">> = field(Req1, "jsonrpc"),
    ?REQ_ID   = field(Req1, "id"),
    false     = proplists:is_defined("error", Props1), % error may not be included

    %% error case
    Req2 = {Props2} = request({"subtract", [1]}),
    false     = proplists:is_defined("result", Props2), % result may not be included
    <<"2.0">> = field(Req2, "jsonrpc"),
    ?REQ_ID   = field(Req2, "id"),
    -32602    = field(Req2, "error.code"),

    %% error case where request isn't read
    Req3 = {Props3} = request("{aa"),
    <<"2.0">> = field(Req3, "jsonrpc"),
    null      = proplists:get_value(<<"id">>, Props3),
    -32700    = field(Req3, "error.code").

notification(_Config) ->
    %% leaving id off is treated as notification
    {no_json, <<"">>} = request("{\"jsonrpc\":\"2.0\", \"method\": \"subtract\", \"params\": [2, 1]}"),

    %% although it's use is discouraged, null is a valid id (in jsonrpc 2.0)
    {Res} = request("{\"id\": null, \"jsonrpc\":\"2.0\", \"method\": \"subtract\", \"params\": [2, 1]}"),
    null = proplists:get_value(<<"id">>, Res).

batch_calls(_Config) ->
    %% success cases
    [Resp1] = request("[{\"jsonrpc\":\"2.0\", \"id\": 344, \"method\":\"subtract\", \"params\": [2,1]}]"),
    1       = field(Resp1, "result"),
    344     = field(Resp1, "id"),

    Resp2   = request("[{\"jsonrpc\":\"2.0\", \"id\": 300, \"method\":\"subtract\", \"params\": [2,1]}"
                      ",{\"jsonrpc\":\"2.0\", \"id\": 400, \"method\":\"subtract\", \"params\": [80,3]}]"),
    2       = length(Resp2),

    %% with notifications
    [Resp3] = request("[{\"jsonrpc\":\"2.0\", \"method\":\"subtract\", \"params\": [2,1]}"
                      ",{\"jsonrpc\":\"2.0\", \"id\": 400, \"method\":\"subtract\", \"params\": [80,3]}]"),
    400     = field(Resp3, "id"),
    77      = field(Resp3, "result"),

    %% only notifications
    {no_json, <<"">>} = request("[{\"jsonrpc\":\"2.0\", \"method\":\"subtract\", \"params\": [2,1]}"
                                ",{\"jsonrpc\":\"2.0\", \"method\":\"subtract\", \"params\": [80,3]}]"),

    %% rpc call with invalid batch (but not empty)
    [Resp4] = request("[1]"),
    null    = field(Resp4, "id"),
    -32600  = field(Resp4, "error.code").

%% ---------------------------------------------------------------------
%% -- common_test callbacks
all() ->
    [{group, old_cb_info},
     {group, new_cb_info}].

groups() ->
    [{all_tests, [], [error_codes, param_structures, response_fields, notification, batch_calls]},
     {old_cb_info, [], [{group, all_tests}]},
     {new_cb_info, [], [{group, all_tests}]}].

%% ---------------------------------------------------------------------
%% -- utilities
request({Method, Params}) ->
    Req = {[{jsonrpc, <<"2.0">>}, {id, ?REQ_ID}, {method, list_to_binary(Method)}, {params, Params}]},
    request(hello2_json:encode(Req));
request(Request) when is_list(Request) ->
    request(list_to_binary(Request));
request(Request) ->
    RespJSON = hello2:run_stateless_binary_request(hello2_test_jsonrpc_2_compliance_handler, Request, []),
    case hello2_json:decode(RespJSON) of
        {ok, DecRespObj, _Rest} -> DecRespObj;
        {error, syntax_error}   -> {no_json, RespJSON}
    end.

field(Object, Field) ->
	Flist = re:split(Field, "\\.", [{return, binary}]),
	lists:foldl(fun (Name, {CurProps}) ->
		    	    proplists:get_value(Name, CurProps)
			    end, Object, Flist).

init_per_group(old_cb_info, Config) ->
    Mod = hello2_test_jsonrpc_2_compliance_handler,
    ok = meck:new(Mod, [non_strict, no_link]),
    ok = meck:expect(Mod, method_info, 0, [#rpc_method{name = subtract}]),
    ok = meck:expect(Mod, param_info,
		     fun(subtract) ->
			     [#rpc_param{name = subtrahend, type = number},
			      #rpc_param{name = minuend, type = number}]
		     end),
    ok = meck:expect(Mod, handle_request,
		     fun(_Context, subtract, [Subtrahend, Minuend]) ->
			     {ok, Subtrahend - Minuend}
		     end),
    [{cb_module, Mod}|Config];

init_per_group(new_cb_info, Config) ->
    Mod = hello2_test_jsonrpc_2_compliance_handler,
    ok = meck:new(Mod, [non_strict, no_link]),
    ok = meck:expect(Mod, hello2_info, fun hello2_test_jsonrpc_compliance_typespec/0),
    ok = meck:expect(Mod, handle_request,
		     fun(_Context, <<"subtract">>, [{_, Subtrahend}, {_, Minuend}]) ->
			     {ok, Subtrahend - Minuend}
		     end),
    [{cb_module, Mod}|Config];

init_per_group(_, Config) ->
    Config.

end_per_group(Group, Config) when Group == old_cb_info; Group == new_cb_info ->
    Mod = proplists:get_value(cb_module, Config),
    meck:unload(Mod),
    ok;
end_per_group(_, _) ->
    ok.
