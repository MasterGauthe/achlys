-module(achlys_task_provider).

-behaviour(gen_server).

%%API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2,
	code_change/3]).

-define(SERVER, ?MODULE).

-record(state,{}).

start_link() -> 
	gen_server:start_link({local, ?SERVER}, ?MODULE, [] , []).

init([]) ->
    ok = schedule_task(),
    {ok , #state{}}.

handle_call(_Request, _From, State) ->
	{reply, ok, State}.

handle_cast({task, Task} , State) ->
    %% Task propagation to the cluster, including self
    achlys:bite(Task),    
    {noreply , State};
handle_cast(_Request , State) ->
    {noreply , State}.


handle_info({task, Task} , State) ->
    %% Task propagation to the cluster, including self
    achlys:bite(Task),
    {noreply , State};
handle_info(_Info , State) ->
    {noreply , State}.


terminate(_Reason, State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

schedule_task() ->
    %% Declare an Achlys task that will be
    %% executed exactly once
    Task = achlys:declare(mytask
        , all
        , single
        , fun() ->
             io:format("Hello Joe ! ~n")
    end),
    %% Send the task to the current server module
    %% after a 5000ms delay
    erlang:send_after(5000, ?SERVER, {task, Task}),
    ok.

pmodnav_task() ->
    %% Declare an Achlys task that will be periodically
    %% executed as long as the node is up
    Task = achlys:declare(pmodnav_task
        , all
        , single
        , fun() ->
            logger:log(notice, "Reading PmodNAV measurements ~n"),
            Acc = pmod_nav:read(acc, [out_x_xl, out_y_xl, out_z_xl]),
            Gyro = pmod_nav:read(acc, [out_x_g, out_y_g, out_z_g]),
            Mag = pmod_nav:read(mag, [out_x_m, out_y_m, out_z_m]),
            Press = pmod_nav:read(alt, [press_out]),
            Temp = pmod_nav:read(alt, [temp_out]),
            Node = erlang:node(),

            F = fun({Acc, Gyro, Mag, Press, Temp, Node}) ->
                    [T] = Temp,
                    NewTemp = ((T * 1.8) + 32),
                    {Acc, Gyro, Mag, Press, [NewTemp], Node}
            end,
            {ok, {SourceId, _, _, _}} = lasp:declare({<<"source">>, state_orset}, state_orset),
            {ok, {DestinationId, _, _, _}} = lasp:declare({<<"destination">>, state_orset}, state_orset),
            lasp:map(SourceId, F, DestinationId),
            lasp:update(SourceId, {add, {Acc, Gyro, Mag, Press, Temp, Node}}, self())
    end).

%% Adds the pmodnav_task to the working set
%% using the Achlys task model
-export([add_pmodnav_task/0]).

add_pmodnav_task() ->
    gen_server:cast(?SERVER 
        , {task, pmodnav_task()}).


