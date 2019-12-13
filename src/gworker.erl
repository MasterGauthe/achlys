-module(gworker).
-author("Crochet Christophe, Van Vracem Gauthier").

-behaviour(gen_server).

-export([start_link/0]).

-export([add_task_exp/0,
        add_task_press/6,
        add_task_temp/6]).

-export([init/1 ,
        show/0,
        handle_call/3 ,
        handle_cast/2 ,
        handle_info/2 ,
        terminate/2 ,
        code_change/3]).

-define(SERVER , ?MODULE).

-record(state , {}).

%%%===================================================================
%%% Default Achlys functions
%%%===================================================================

start_link() ->
  gen_server:start_link({local , ?SERVER} , ?MODULE , [] , []).

add_task_exp() ->
  gen_server:cast(?SERVER
  , {task, task_exp()}).

add_task_temp(Mode1,Mode2,Len,SampleRate,LB,UB) ->
  gen_server:cast(?SERVER
  , {task, temperature(Mode1,Mode2,Len,SampleRate,LB,UB)}).

add_task_press(Mode1,Mode2,Len,SampleRate,LB,UB) ->
  gen_server:cast(?SERVER
  , {task, pressure(Mode1,Mode2,Len,SampleRate,LB,UB)}).

init([]) ->
  ok = loop_schedule_task(3, 1000),
  logger:log(critical, "Running provider ~n"),
  {ok , #state{}}.

handle_call(_Request , _From , State) ->
  {reply , ok , State}.

handle_cast({task, Task} , State) ->
  logger:log(critical, "Received task cast signal ~n"),
  %% Task propagation to the cluster, including self
  achlys:bite(Task),
  {noreply , State};
handle_cast(_Request , State) ->
  {noreply , State}.

handle_info({task, Task} , State) ->
  logger:log(critical, "Received task signal ~n"),
  %% Task propagation to the cluster, including self
  achlys:bite(Task),
  {noreply , State};
handle_info(_Info , State) ->
  {noreply , State}.

terminate(_Reason , _State) ->
  ok.

code_change(_OldVsn , State , _Extra) ->
  {ok , State}.

%%%===================================================================
%%% Exemple loop task
%%%===================================================================

loop_schedule_task(0, Time) ->
    io:format("Finish! ~n"),
    ok;
loop_schedule_task(Count, Time) ->
    Task = achlys:declare(mytask
    , all
    , single
    , fun() ->
      println(Count),
      loop_schedule_task(Count-1, Time)
    end),
    {task, Task},
    %% Send the task to the current server module
    %% after a 5000ms delay
    erlang:send_after(Time, ?SERVER, {task, Task}),
    ok.

%%%===================================================================
%%% Task about temperature measurements
%%%===================================================================

temperature(Mode1, Mode2, Len, SampleRate,LB,UB) ->
    Task = achlys:declare(temperature,
    all,
    permanent,
    fun() ->
      logger:log(notice, "Reading PmodNAV temperature interval ~n"),
      SourceId = {<<"source">>, state_gset},
      {ok , {_SourceId , _Meta , _Type , _State }} = lasp : declare (SourceId , state_gset),

      Buffer = lists:foldl(fun
        (Elem,AccIn) ->
          timer : sleep(SampleRate), %10 measurements per minute
          %Temp = pmod_nav:read(acc,[out_temp]),
          Temp = rand:uniform(100),
          if
            Temp < UB ->
              if
                Temp > LB -> [Temp] ++ AccIn;
                true -> [LB] ++ AccIn
              end;
            true -> [UB] ++ AccIn
          end
        end,[],lists:seq(1,Len)),

        Name = node(),
        Pid = self(),

        case Mode1 of
          current ->
              {Best,Count,S,Length} = initGlobalVar(state_gset),
              CurrentElem = getElem(Mode2, Length, Best, S),
              Current = pmod_nav:read(acc,[out_temp]),
              U = updateElem(Mode2,Current,CurrentElem,Best),
              lasp:update(SourceId , {add , {Current , Name}}, Pid),
              lasp:update(Count, increment, self()),
              println(Current);
          min ->
              {Best,Count,S,Length} = initGlobalVar(state_gset),
              MinElem = getElem(Mode2, Length, Best, S),
              Min = lists:min(Buffer),
              U = updateElem(Mode2,Min,MinElem,Best),
              lasp:update(SourceId , {add , {Min , Name}}, Pid),
              lasp:update(Count, increment, self()),
              println("Updated Elem = ",U),
              println("Local Min = ",Min);
          max ->
              {Best,Count,S,Length} = initGlobalVar(state_gset),
              MaxElem = getElem(Mode2, Length, Best, S),
              Max = lists:max(Buffer),
              U = updateElem(Mode2,Max,MaxElem,Best),
              lasp:update(SourceId , {add , {Max , Name}}, Pid),
              lasp:update(Count, increment, self()),
              println("Updated Elem = ",U),
              println("Local Max = ",Max);
          mean ->
              {Best,Count,S,Length} = initGlobalVar(state_gset),
              MeanElem = getElem(Mode2, Length, Best, S),
              Mean = average(Buffer),
              U = updateElem(Mode2,Mean,MeanElem,Best),
              lasp:update(SourceId , {add , {Mean , Name}}, Pid),
              lasp:update(Count, increment, self()),
              println("Updated Elem = ",U),
              println("Local Mean = ",Mean);
          variance ->
              {Best,Count,S,Length} = initGlobalVar(state_gset),
              VarElem = getElem(Mode2, Length, Best, S),
              Var = variance(Buffer),
              U = updateElem(Mode2,Var,VarElem,Best),
              lasp:update(SourceId , {add , {Var , Name}}, Pid),
              lasp:update(Count, increment, self()),
              println("Updated Elem = ",U),
              println("Local Var = ",Var)
          end,
          println(" ")
      end).

%%%===================================================================
%%% Task about pressure measurements
%%%===================================================================

pressure(Mode1, Mode2, Len, SampleRate,LB,UB) ->
  Task = achlys:declare(temperature,
  all,
  permanent,
  fun() ->
    logger:log(notice, "Reading PmodNAV temperature interval ~n"),
    SourceId = {<<"source">>, state_gset},
    {ok , {_SourceId , _Meta , _Type , _State }} = lasp : declare (SourceId , state_gset),

    Buffer = lists:foldl(fun
      (Elem,AccIn) ->
        timer : sleep(SampleRate), %10 measurements per minute
        %Temp = pmod_nav:read(acc,[press_out]),
        Press = rand:uniform(100),
        if
          Press < UB ->
            if
              Press > LB -> [Press] ++ AccIn;
              true -> [LB] ++ AccIn
            end;
          true -> [UB] ++ AccIn
        end
      end,[],lists:seq(1,Len)),

      Name = node(),
      Pid = self(),

      case Mode1 of
        current ->
            {Best,Count,S,Length} = initGlobalVar(state_gset),
            CurrentElem = getElem(Mode2, Length, Best, S),
            Current = pmod_nav:read(acc,[out_press]),
            U = updateElem(Mode2,Current,CurrentElem,Best),
            lasp:update(SourceId , {add , {Current , Name}}, Pid),
            lasp:update(Count, increment, self()),
            println(Current);
        min ->
            {Best,Count,S,Length} = initGlobalVar(state_gset),
            MinElem = getElem(Mode2, Length, Best, S),
            Min = lists:min(Buffer),
            U = updateElem(Mode2,Min,MinElem,Best),
            lasp:update(SourceId , {add , {Min , Name}}, Pid),
            lasp:update(Count, increment, self()),
            println("Updated Elem = ",U),
            println("Local Min = ",Min);
        max ->
            {Best,Count,S,Length} = initGlobalVar(state_gset),
            MaxElem = getElem(Mode2, Length, Best, S),
            Max = lists:max(Buffer),
            U = updateElem(Mode2,Max,MaxElem,Best),
            lasp:update(SourceId , {add , {Max , Name}}, Pid),
            lasp:update(Count, increment, self()),
            println("Updated Elem = ",U),
            println("Local Max = ",Max);
        mean ->
            {Best,Count,S,Length} = initGlobalVar(state_gset),
            MeanElem = getElem(Mode2, Length, Best, S),
            Mean = average(Buffer),
            U = updateElem(Mode2,Mean,MeanElem,Best),
            lasp:update(SourceId , {add , {Mean , Name}}, Pid),
            lasp:update(Count, increment, self()),
            println("Updated Elem = ",U),
            println("Local Mean = ",Mean);
        variance ->
            {Best,Count,S,Length} = initGlobalVar(state_gset),
            VarElem = getElem(Mode2, Length, Best, S),
            Var = variance(Buffer),
            U = updateElem(Mode2,Var,VarElem,Best),
            lasp:update(SourceId , {add , {Var , Name}}, Pid),
            lasp:update(Count, increment, self()),
            println("Updated Elem = ",U),
            println("Local Var = ",Var)
        end,
        println(" ")
    end).

%%%===================================================================
%%%  Exemple Task
%%%===================================================================

task_exp() ->
    Task = achlys:declare(task_exp
    , all
    , permanent
    , fun() ->
        logger:log(notice, "Reading PmodNAV pressure interval ~n"),
        Temp = rand:uniform(100),
        Node = erlang:node(),
        {ok, {SourceId, _, _, _}} = lasp:declare({<<"source">>, state_gset}, state_gset),
        {ok, {BestMax, _, _, _}} = lasp:declare({<<"best">>, state_gset}, state_gset),
        {ok, {Count, _, _, _}} = lasp:declare({<<"gcountvar">>, state_gcounter}, state_gcounter),
        {ok , Smax} = lasp:query(BestMax),
        {ok, Length} = lasp:query(Count),
        if
            Length == 0 -> lasp:update(BestMax, {add, 1}, self()),
            Max = 1;
            true -> Max = lists:max(sets:to_list(Smax))
        end,
        println(Max),
        if
            Temp > Max -> lasp:update(BestMax, {add, Temp}, self());
            true -> ok
        end,
        lasp:update(SourceId, {add, {Temp, Node}}, self()),
        lasp:update(Count, increment, self())
        end).

%%%===================================================================
%%% Helpers functions
%%%===================================================================

show() ->
  {ok, {Best, _, _, _}} = lasp:declare({<<"best">>, state_gset}, state_gset),
  {ok, Best0} = lasp:query(Best),
  io:format("BEST: " ++ "~p~n", [sets:to_list(Best0)]).

%%--------------------------------------------------------------------

println(What) -> io:format("~p~n", [What]).
println(Text,What) -> io:format(Text ++ "~p~n", [What]).

%%--------------------------------------------------------------------

%return the average of a list
average(List) ->
  lists:sum(List) / length(List).

%return the variance of a list
variance(List) ->
  Mean = average(List),
  NewList = lists:flatmap(fun(Elem)->
                              [(abs(Elem-Mean))*(abs(Elem-Mean))]
                          end, List),
  average(NewList).

%%--------------------------------------------------------------------

%Initializes lasp's variables : global best value and global counter
%return :
% - Best  = global lasp set "best"
% - Count = global lasp counter "gcountvar"
% - S     = Set of Best
% - Length= length of set S
initGlobalVar(Set) ->
  {ok, {Best, _, _, _}} = lasp:declare({<<"best">>, Set}, Set),
  {ok, {Count, _, _, _}} = lasp:declare({<<"gcountvar">>, state_gcounter}, state_gcounter),
  {ok , S} = lasp:query(Best),
  {ok, Length} = lasp:query(Count),
  {Best,Count,S,Length}.

%%--------------------------------------------------------------------

%return of the Best set value that satisfy the Mode
getElem(Mode, Length, Best, S) ->
  case Mode of
    min      -> if
                Length == 0 -> lasp:update(Best, {add, 100}, self()),
                               Elem = 100;
                true -> Elem = lists:min(sets:to_list(S))
              end;
    max      -> if
                Length == 0 -> lasp:update(Best, {add, 0}, self()),
                               Elem = 0;
                true -> Elem = lists:max(sets:to_list(S))
              end;
    mean     -> if
                Length == 0 -> lasp:update(Best, {add, 0}, self()),
                               Elem = 0;
                true -> Elem = average(sets:to_list(S))
              end;
    variance -> if
                Length == 0 -> lasp:update(Best, {add, 0}, self()),
                               Elem = 0;
                true -> Elem = variance(sets:to_list(S))
              end
  end,
  Elem.

%%--------------------------------------------------------------------

%update the global var lasp if the local variable is better than the global
%one
updateElem(Mode,Value,Elem,Best) ->
  case Mode of
    min      -> if
                  Value < Elem -> lasp:update(Best, {add, Value}, self()),
                                  UpdateEle = Value;
                  true -> UpdateEle = Elem
                end;
    max      -> if
                  Value > Elem -> lasp:update(Best, {add, Value}, self()),
                                  UpdateEle = Value;
                  true -> UpdateEle = Elem
                end;
    mean     -> Value2 = (Value + Elem) / 2,
                lasp:update(Best, {add, Value2}, self()),
                UpdateEle = (Value + Elem) / 2;
    variance -> lasp:update(Best, {add, variance([Value,Elem])}, self()),
                UpdateEle = variance([Value,Elem])
end,
{UpdateEle}.
