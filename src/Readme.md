# Documentation
## gworker

<p align="center">
  <img src="resources/presentation_gworker.jpg" alt="EDoc"/>
</p>

### Usage 

Command to initialize the mote : 
- gworker:start_link().
- gworker:add_task_exp().
- gworker:add_task_temp(Mode1,Mode2,Len,SampleRate,LB,UB). % for temperature
- gworker:add_task_press(Mode1,Mode2,Len,SampleRate,LB,UB). % for pressure

With arguments : 
- Mode1      = {current,min,max,mean,variance}
- Mode2      = {current,min,max,mean,variance}
- Len        = Size of the local buffer use for aggregation for each mote
- SampleRate = Duration in ms between each sensors activation
- LB         = Lower bound for the sensor
- UB         = Upper bound for the sensor







## earthquake