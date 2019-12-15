-module(earthquake).

-author("Gauthier VAN VRACEM, Christophe CROCHET").

-behaviour(gen_server).

-export([start_link/0]).

-export([show/0]).

-export([init/1 ,
handle_call/3 ,
handle_cast/2 ,
handle_info/2 ,
terminate/2 ,
code_change/3]).

-define(SERVER , ?MODULE).

-record(state , {}).

%%%===================================================================
%%% Default achlys functions
%%%===================================================================

start_link() ->
  gen_server:start_link({local , ?SERVER} , ?MODULE , [] , []).

init([]) ->
  ok = task_1(3),
  logger:log(critical, "Running provider ~n"),
  {ok , #state{}}.

handle_call(_Request , _From , State) ->
  {reply , ok , State}.

handle_cast({task, Task} , State) ->
  logger:log(critical, "Received task cast signal ~n"),
  achlys:bite(Task),
  {noreply , State};
handle_cast(_Request , State) ->
  {noreply , State}.

handle_info({task, Task} , State) ->
  logger:log(critical, "Received task signal ~n"),
  achlys:bite(Task),
  {noreply , State};
handle_info(_Info , State) ->
  {noreply , State}.

terminate(_Reason , _State) ->
    ok.

code_change(_OldVsn , State , _Extra) ->
    {ok , State}.

%%%===================================================================
%%% Main Task
%%%===================================================================

task_1(Threshold) ->
    Task = achlys:declare(task_1
    , all
    , permanent
    , fun() ->
      Node = erlang:node(),
      NbNodes = length(erlang:nodes())+1,
      {ok, {QuakeFlag, _, _, _}} = lasp:declare({<<"quake">>, state_ewflag}, state_ewflag),
      {ok, {NodesShake, _, _, _}} = lasp:declare({<<"shake">>, state_orset}, state_orset),
      {ok, {History, _, _, _}} = lasp:declare({<<"history">>, state_gset}, state_gset),

      MoveTest = move_detection_rand(10,Threshold),
      %% MoveTest = move_detection(-1.5, 1.5),
      %% MoveTest = move_detection_deviation(2.0),
      if
          MoveTest -> lasp:update(NodesShake, {add, Node}, self());
          %grisp_led : color (1, green );
          true -> lasp:update(NodesShake, {rmv, Node}, self())
          %grisp_led : color (2, red )
      end,
      {ok, CountShakes} = lasp:query(NodesShake),
      L = length(sets:to_list(CountShakes)),
      if
          (L == NbNodes) and (L > 0) -> lasp:update(QuakeFlag, enable, self()),
          lasp:update(History, {add,  get_date() }, self()),
          println("Earthquake detected !");
          true -> lasp:update(QuakeFlag, disable, self()),
          println("nothing")
      end

      end),
      {task, Task},
      gen_server:cast(?SERVER, {task, Task}),
      ok.

%%%===================================================================
%%% Helpers functions
%%%===================================================================

move_detection(LB,UB) ->
    logger:log(notice, "Reading PmodNAV Accelerometer ~n"),
    Xsample = pmod_nav:read(acc, [out_x_xl]),
    Ysample = pmod_nav:read(acc, [out_y_xl]),
    Zsample = pmod_nav:read(acc, [out_z_xl]),
    Maxsample = lists:max((Xsample ++ Ysample) ++ Zsample),
    Minsample = lists:min((Xsample ++ Ysample) ++ Zsample),
    if
        (Minsample < LB) or (Maxsample > UB) -> true;
        true -> false
    end.

%%--------------------------------------------------------------------

move_detection_deviation(Threshold) ->
    Buffer = lists:foldl(fun
    (Elem,Acc) ->
        timer : sleep(50),
        SampleY = pmod_nav:read(acc, [out_y_g]),
        SampleZ = pmod_nav:read(acc, [out_z_g]),
        [Y] = SampleY,
        [Z] = SampleZ,
        Ro = math:atan2(Y,Z),
        [Ro] ++ Acc
    end,[],lists:seq(1,5)),
    SD = math:sqrt(variance(Buffer)),
    if
        (SD > Threshold) -> true;
        true -> false
    end.

%%--------------------------------------------------------------------

move_detection_rand(Range, Threshold) ->
    R0 = rand:uniform(Range),
    R1 = rand:uniform(Range),
    if
        abs(R1- R0) > Threshold -> true;
        true -> false
    end.

%%--------------------------------------------------------------------

print_query_set(Id, Text) ->
    {ok , S} = lasp:query(Id) ,
    io:format(Text ++ "~p~n", [sets:to_list(S)]).

%%--------------------------------------------------------------------

print_query(Id, Text) ->
    {ok , S} = lasp:query(Id) ,
    io:format(Text ++ "~p~n", [S]).

%%--------------------------------------------------------------------

get_date() ->
    {{Y,M,D},{Hour,Min,Sec}} = calendar:now_to_local_time(erlang:now()),
    {Hour,Min}.

%%--------------------------------------------------------------------

show() ->
    {ok, {QuakeFlag, _, _, _}} = lasp:declare({<<"quake">>, state_ewflag}, state_ewflag),
    {ok, {NodesShake, _, _, _}} = lasp:declare({<<"shake">>, state_orset}, state_orset),
    {ok, {History, _, _, _}} = lasp:declare({<<"history">>, state_gset}, state_gset),
    io:format("Number of nodes: " ++ "~p~n", [length(erlang:nodes())+1]),
    print_query_set(NodesShake, "Shaking nodes:  "),
    print_query_set(History, "List of earthquakes:  "),
    print_query(QuakeFlag, "Earthquake flag: ").

%%--------------------------------------------------------------------

println(What) -> io:format("~p~n", [What]).

%%--------------------------------------------------------------------

average(List) ->
    lists:sum(List) / length(List).

%%--------------------------------------------------------------------

variance(List) ->
    Mean = average(List),
    NewList = lists:flatmap(fun(Elem)->
                              [(abs(Elem-Mean))*(abs(Elem-Mean))]
                          end, List),
    average(NewList).
