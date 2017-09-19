%%
%% Copyright (c) 2013-2017 EMQ Enterprise Inc.
%%

-module(emq_mod_subscription).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(emqttd_gen_mod).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_protocol.hrl").

-export([load/1, on_client_connected/3, unload/1]).

-define(TAB, ?MODULE).

%%--------------------------------------------------------------------
%% Load/Unload Hook
%%--------------------------------------------------------------------

load(Topics) ->
    emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [Topics]).

on_client_connected(?CONNACK_ACCEPT, Client = #mqtt_client{client_id  = ClientId,
                                                           client_pid = ClientPid,
                                                           username   = Username}, Topics) ->

    Replace = fun(Topic) -> rep(<<"%u">>, Username, rep(<<"%c">>, ClientId, Topic)) end,
    TopicTable = [{Replace(Topic), Qos} || {Topic, Qos} <- Topics],
    {ok, Redis} = eredis:start_link(),
    FinalList = case eredis:q(Redis, ["sMembers", "mqtt_sub:" ++ Username]) of
                {ok, OurTopics} ->
                  case listAppend(TopicTable, OurTopics) of
                    {ok, AppendedList} when is_list(AppendedList) ->
                      AppendedList;
                    {ok,_} ->
                      TopicTable;
                    {error} ->
                      TopicTable
                  end;
                {error,Reason} ->
                  TopicTable
                  end,
    ClientPid ! {subscribe, FinalList},
    {ok, Client};

on_client_connected(_ConnAck, _Client, _State) ->
    ok.

unload(_) ->
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3).

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------

listAppend(DefaultTopic,NewTopics) when length(NewTopics) > 0 ->
  ListLast = lists:last(NewTopics),
  LastDropped = lists:droplast(NewTopics),
  Result = case listAppend(DefaultTopic,LastDropped) of
             {ok,NewList} ->
               lists:append(NewList,[{ListLast,2}]);
             {error} ->
               lists:append(DefaultTopic,[{ListLast,2}])
           end,
  {ok,Result};
listAppend(_,_) ->
{error}.

rep(<<"%c">>, ClientId, Topic) ->
    emqttd_topic:feed_var(<<"%c">>, ClientId, Topic);
rep(<<"%u">>, undefined, Topic) ->
    Topic;
rep(<<"%u">>, Username, Topic) ->
    emqttd_topic:feed_var(<<"%u">>, Username, Topic).

