# ABWLog

I've had a fair bit of free time this week, so I spent some of it working on my PowerShell logging module.

It is fairly epic at 200 lines now. On the one hand it does literally everything I have ever, ever wanted out of a logger. But it's also quick and easy for the most simple use cases, like the below.

## Basic use
To get started, all I need to do is create a new log object and add an event to it:
```
 PS /Users/alex/scripts> $log = [ABWLog]::new("AlexLog")
 PS /Users/alex/scripts> $log.AddEvent("This is the best log event ever!")
 
 DateTime               Category Message                          EventError
 --------               -------- -------                          ----------
 17/4/20 10:09:45 am Unspecified This is the best log event ever!
```
New log events are sent to a buffer which can be accessed using the `Events()` method:
```
PS /Users/alex/scripts> $log.Events()

DateTime              Category Message                          EventError
--------              -------- -------                          ----------
17/4/20 9:49:54 am Unspecified This is the best log event ever!
```
## File streaming

If I want to buffer to a file as well, I just call `StartLogFileStream()`:
```
PS /Users/alex/scripts> $log.StartLogFileStream()
PS /Users/alex/scripts> $log.AddEvent("This event will appear in the logfile.")

DateTime               Category Message                                EventError
--------               -------- -------                                ----------
17/4/20 10:12:54 am Unspecified This event will appear in the logfile. 
```
By default this writes to an automatically-generated filename under the working directory (but can be customised by setting the `StreamFile` property). Log files look like the below:
```
PS /Users/alex/scripts> Get-Content $log.StreamFile
17/4/20 10:12 am : This event will appear in the logfile.
```
## Categories
That whitespace in the file output is to allow some room to write the event categories. The following categories are defined by the module:
```
PS /Users/alex/scripts> [System.Enum]::GetValues([ABWEventCategory])|%{("{0} = {1}" -f [string]$_,[int]$_)}
Unspecified = 0
Debug = 10
Information = 30
Success = 50
Warning = 70
Error = 90
Milestone = 99
```
Categories can be set manually when adding events, if you'd like:
```
PS /Users/alex/scripts> $(
>>     $log.AddEvent("The script is starting!",[ABWEventCategory]::Milestone)    
>>     $log.AddEvent([ABWEventCategory]::Warning, "We're about to see an error!")
>>     New-Item "/" -ErrorAction SilentlyContinue
>>     $log.AddEvent($Error[0])
>> )

DateTime             Category Message                                        EventError
--------             -------- -------                                        ----------
17/4/20 10:15:11 am Milestone The script is starting!                        
17/4/20 10:15:11 am   Warning We're about to see an error!                   
17/4/20 10:15:11 am     Error The file '/Users/alex/scripts' already exists. The file '/Users/alex/scripts' already exists.
```
## Errors
Notice how when we supplied an ErrorRecord above, a couple of things happened. Firstly the event category was set to "Error" automatically. You can override this by specifying it when you `AddLog()`.
Secondly, the Message property was set to the ErrorRecord's exception message. Again, this can be overridden if you specify a message in `AddLog()`.
Finally, the EventError property is populated. At first glance this looks like a duplicate of the Message field, but rather than being a string it's actually storing the ErrorRecord itself. This can be useful if you want to pull exception details out of a log entry when debugging after the fact:
```
PS /Users/alex/scripts> $log.Events()[2].EventError.GetType()
                                                                                 
IsPublic IsSerial Name                                     BaseType              
-------- -------- ----                                     --------
True     True     ErrorRecord                              System.Object
    
PS /Users/alex/scripts> $log.Events()[2].EventError.Exception.StackTrace
   at Interop.ThrowExceptionForIoErrno(ErrorInfo errorInfo, String path, Boolean isDirectory, Func`2 errorRewriter)
   at Microsoft.Win32.SafeHandles.SafeFileHandle.Open(String path, OpenFlags flags, Int32 mode)
   at System.IO.FileStream..ctor(String path, FileMode mode, FileAccess access, FileShare share, Int32 bufferSize, FileOptions options)
   at System.IO.FileStream..ctor(String path, FileMode mode, FileAccess access, FileShare share)
   at Microsoft.PowerShell.Commands.FileSystemProvider.NewItem(String path, String type, Object value)
```
## Exporting events to other formats
Using the `ConvertToString()` method shows exactly the same text as would be streamed to a log file:
```
PS /Users/alex/scripts> $log.ConvertToString()
----------
The script is starting!
----------
 17/4/20 10:16 am Warning       : We're about to see an error!
 17/4/20 10:16 am Error         : The file '/Users/alex/scripts' already exists.
```
(By the way, "Milestone" category events are meant to break up text log files and are outputted as headers as above.)

There's also `ConvertToJson()`, `ConvertToCsv()` and `ConvertToHtml()` which output to those formats. JSON in particular is great for detail as it includes the entire ErrorRecord object.

## Event-based processing of... (log) events
Say I need to some custom event handling that the module can't handle by itself. This can be achieved through raising PowerShell events to the queue whenever a log entry is added:
```
PS /Users/alex/scripts> $log.CreatePSEvents = $true
PS /Users/alex/scripts> $log.AddEvent("This event will be sent to the PowerShell event engine.")

DateTime               Category Message                                                 EventError
--------               -------- -------                                                 ----------
17/4/20 10:20:22 am Unspecified This event will be sent to the PowerShell event engine. 

PS /Users/alex/scripts> (Get-Event)[0]

ComputerName     : 
RunspaceId       : 28335f97-62c6-4d91-844c-97823ed08e70
EventIdentifier  : 5
Sender           : ABWLog
SourceEventArgs  : 
SourceArgs       : {}
SourceIdentifier : ABWLog.AlexLog.Event_Added
TimeGenerated    : 17/4/20 10:20:22 am
MessageData      : {Event, Log}
```
The event will be raised with a SourceIdentifier of `ABWLog.{Log Identifier}.Event_Added` and contains a hashtable of the entire log object along with the event that was just raised.

In the below example, I will subscribe to this event, and use a custom ScriptBlock to send log events to different logfiles based on their category:
```
PS /Users/alex/scripts> Register-EngineEvent -SourceIdentifier "ABWLog.AlexLog.Event_Added" -Action {
>>     $LogEvent = $event.MessageData.Event
>>     if ($LogEvent.Category -eq [ABWEventCategory]::Error) { Add-Content -Path "Errors.log" -Value $LogEvent }
>>     else { Add-Content -Path "EverythingElse.log" -Value $LogEvent }
>> }

Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
--     ----            -------------   -----         -----------     --------             -------
2      ABWLog.AlexLog…                 NotStarted    False                                …

PS /Users/alex/scripts> $log.AddEvent([ABWEventCategory]::Error, "This is an error")

DateTime            Category Message          EventError
--------            -------- -------          ----------
17/4/20 10:22:43 am    Error This is an error 

PS /Users/alex/scripts> $log.AddEvent("This is not an error")

DateTime               Category Message              EventError
--------               -------- -------              ----------
17/4/20 10:22:49 am Unspecified This is not an error 

PS /Users/alex/scripts> Get-Content ./Errors.log
17/4/20 10:23 am Error         : This is an error

PS /Users/alex/scripts> Get-Content ./EverythingElse.log
17/4/20 10:23 am : This is not an error
```

## Quiet, please!
By default `AddLog()` will return the actual event object that was added. To suppress this, set the `Quiet` property:
```
PS /Users/alex/scripts> $log.AddEvent("This event is loud!")

DateTime               Category Message             EventError
--------               -------- -------             ----------
17/4/20 10:25:31 am Unspecified This event is loud! 

PS /Users/alex/scripts> $log.Quiet = $true
PS /Users/alex/scripts> $log.AddEvent("This event is quiet...")
PS /Users/alex/scripts> 
```
## Working with Event objects
You can instantiate event objects manually if you want:
```
PS /Users/alex/scripts> $evt = [ABWEvent]::new(
>>     [ABWEventCategory]::Debug,
>>     "Look dad I'm scripting now!",
>>     $null
>> )
PS /Users/alex/scripts> $evt

DateTime            Category Message                     EventError
--------            -------- -------                     ----------
17/4/20 10:30:54 am    Debug Look dad I'm scripting now! 

```
Event objects can be added to a log using `AddLog()`. This lets you do things like copying from one log to another, or adding the same event object to multiple logs.
```
PS /Users/alex/scripts> $(                         
>>     $log1.AddEvent($evt)          
>>     $log2.AddEvent($evt)          
>> )        
    
DateTime            Category Message                     EventError
--------            -------- -------                     ----------
17/4/20 10:38:07 am    Debug Look dad I'm scripting now! 
17/4/20 10:38:07 am    Debug Look dad I'm scripting now! 

```
If we decide to modify the event object later, it will be updated in all the log objects we added it to (but not file streams):
```
PS /Users/alex/scripts> $evt.Message = $evt.Message -replace "dad","mum"
PS /Users/alex/scripts> $(               
>>     $log1.Events()                
>>     $log2.Events()
>> )

DateTime            Category Message                     EventError
--------            -------- -------                     ----------
17/4/20 10:38:07 am    Debug Look mum I'm scripting now! 
17/4/20 10:38:07 am    Debug Look mum I'm scripting now! 
```
