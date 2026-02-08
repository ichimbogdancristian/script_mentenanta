how i like this project to run and what you should implement
temp_files folder must be created in the extracted repo folder
maintenance.log should be like a powershell transcript for the entire project
when the orchestrator is running it should display a menu as fallows
Stage 1 gadder System Inventory
0 - run all Type1 modules
1 - Type1 no 1
2 - Type1 no 2
3 - Type1 no 3
......
with a 10 s countdown, if no user input (1, 2, 3 ....)
it should run 0 - run all Type1 modules and create inventory files for the respective module
Type1 and Type2 modules must run OS specific actions paths and tools
These logs should be processed and determine what actions should be run by the Type2 modules
If there are no results from processing the logs for a certain module that module should
announce that there are no actions to be taken and should be skipped
Do a comprehensive analysis of Type1 and Type2 modules /core and /config folders
Make sure the Type1 modules provide the necessary information for the Type2 modules
thru the end of the project execution a nice HTML report should be created
containing all the actions the project has taken on that run and place a copy of that report on the location where the script.bat is
After the report is copied it should display a 120 countdown
if no user interaction it should remove the repo folder and restart the system
if user interaction it should abort the countdown and leave everything as is

Remember this project must be able to run unattended on any Windows 10/11 computer
