enum ABWEventCategory {
    Unspecified = 0
    Debug       = 10
    Information = 30
    Success     = 50
    Warning     = 70
    Error       = 90
    Milestone   = 99
}

class ABWLog {

    #Properties:
    #--

    hidden [ABWEvent[]] $c_Events
    hidden [System.IO.StreamWriter] $c_StreamWriter
    hidden [System.Management.Automation.PSEventJob] $c_StreamEvent
    hidden [bool] $c_FileStreamIsRunning
    [string]$Id
    [System.IO.FileInfo] $StreamFile
    [bool] $CreatePSEvents
    [bool] $Quiet

    #Initialisation:
    #--

    ABWLog(
        [string]$Identifier
        ) {
        
        if ($Identifier -match "^[^.][A-z0-9\\-\\_\\.]+[^.]$") {
            $this.Id = $Identifier
        }
        else {
            Throw [System.ArgumentException] "A valid identifier string must be supplied. Alphanumeric characters, hypens, underscores and periods are allowed."
        }
    }

    [string]ToString() { return $this.Id }

    [ABWEvent[]] Events() {
        return $this.c_Events
    }

    #AddEvent overrides:
    #--

    #Add an event directly using an ABWEvent object
    [ABWEvent]AddEvent(
        [ABWEvent]$Event
        ) {
        return $this.EventAdder($Event)
    }

    #Create three generic overrides and generate a Hashtable used by the helper function
    #This is hacky, but PowerShell support for method overrides based on parameter type is lacking
    [ABWEvent]AddEvent($arg1){
        return $this.EventAdder($this.GenerateParamTable(@($arg1)))
    }

    [ABWEvent]AddEvent($arg1,$arg2){
        return $this.EventAdder($this.GenerateParamTable(@($arg1,$arg2)))
    }

    [ABWEvent]AddEvent($arg1,$arg2,$arg3){
        return $this.EventAdder($this.GenerateParamTable(@($arg1,$arg2,$arg3)))
    }

    hidden [Hashtable] GenerateParamTable(
        [System.Array]$arr
        ) {
        $private:ret=@{}
        $arr | % {
            if ($_.GetType() -eq [ABWEventCategory]) {$ret.Add("Category",$_)}
            elseif ($_.GetType() -eq [System.Management.Automation.ErrorRecord]) {$ret.Add("EventError",$_)}
            elseif ($_.GetType() -eq [string]){$ret.Add("Message",$_)}
            else {Throw [System.ArgumentException] "Invalid parameter type supplied: $($_.GetType())"}
            }
        return $ret
    }

    #Helper functions that actually add the events:
    #--

    #One for the Hashtables generated above
    hidden [ABWEvent] EventAdder ([Hashtable]$EventParameters){
        if (-not ($EventParameters.Message -or $EventParameters.EventError)) { Throw [System.ArgumentException] "A valid message string or ErrorRecord must be supplied, at minimum."} #tidy

        $new_event = [ABWEvent]::new(
            $(if ($EventParameters.Category) {$EventParameters.Category} else {
                if ($EventParameters.EventError) {[ABWEventCategory]::Error} else {[ABWEventCategory]::Unspecified}}
                ),
            $(if ($EventParameters.Message) {$EventParameters.Message} else {$EventParameters.EventError.ToString()}),
            $EventParameters.EventError
            )
        return $this.EventAdder($new_event)
    }

    #And finally, one for direct event addition (this is called by the EventAdder for Hashtables)
    hidden [ABWEvent] EventAdder ([ABWEvent]$Event) {
        $this.c_Events += $Event

        if ($this.CreatePSEvents){
            New-Event -SourceIdentifier ("ABWLog.{0}.Event_Added" -f $this.Id) -Sender "ABWLog" -MessageData @{Log=$this;Event=$Event}
        }
        if ($this.c_FileStreamIsRunning){
            New-Event -SourceIdentifier ("ABWLog.{0}.FileStream_Event_Added" -f $this.Id) -Sender "ABWLog" -MessageData @{Log=$this;Event=$Event}
        }
        if (-not $this.Quiet) { $private:ret = $Event }
        return $ret
    }

    #Methods to dump the event lists in various formats:
    #--

    [string] ConvertToHtml() { return ($this.Events() | ConvertTo-Html) }
    [string] ConvertToCsv() { return ($this.Events() | ConvertTo-Csv) }
    [string] ConvertToJson() { return ($this.Events() | ConvertTo-Json) }
    [string] ConvertToString() { return ($this.Events() | % { $_.ToString() } ) }


    #File streaming functionality:
    #--

    [bool]FileStreamIsRunnng() {
        return $this.c_FileStreamIsRunning
    }

    [void] StartLogFileStream () {
        if ($this.c_FileStreamIsRunning){
            Throw [System.IO.IOException] "The stream is already running."
        }
        else{
            if (-not $this.StreamFile) {
                $this.StreamFile = "$(Get-Location)/$($this.Id)-$(Get-Date -UFormat "%Y%m%d%H%M%S").log"
            }
            $this.c_StreamWriter = $this.StreamFile.CreateText()
                $this.c_StreamEvent = Register-EngineEvent -SourceIdentifier "ABWLog.$($this.Id).FileStream_Event_Added" -Action {
                    $Event.MessageData.Log.c_StreamWriter.Write($Event.MessageData.Event)
                    $Event.MessageData.Log.c_StreamWriter.Flush()
                }
            $this.c_FileStreamIsRunning = $true
        }
    }

    [void] StopLogFileStream () {
        if ($this.c_FileStreamIsRunning) {
            Unregister-Event -SourceIdentifier "ABWLog.$($this.Id).FileStream_Event_Added"
            $this.c_FileStreamIsRunning = $false
            $this.c_StreamWriter.Close()
            $this.StreamFile = $null
        }
        else {
            Throw [System.IO.FileNotFoundException] "No filestream is currently running."
       }
    }

}

class ABWEvent {

    #Properties:
    #--

    [DateTime]$DateTime
    [ABWEventCategory]$Category
    [string]$Message
    [System.Management.Automation.ErrorRecord]$EventError

    #Initialisation:
    #--

    ABWEvent([ABWEventCategory]$Category,[string]$Message,[System.Management.Automation.ErrorRecord]$EventError) {
        #$this.init([ABWEventCategory]$Category,$Message,$EventError)
        $this.DateTime = Get-Date
        $this.Category = $Category
        $this.Message = $Message
        $this.EventError = $EventError
    }

    [string]ToString(){
        $private:Seperator = "----------"
        if ($this.Category -eq [ABWEventCategory]::Milestone) {
            $private:str = "$Seperator`n$($this.Message)`n$Seperator`n"
        } else {
            $private:str = "$($this.DateTime.ToString("g"))$(" $(if(-not $this.Category -eq [ABWEventCategory]::Unspecified){"$($this.Category)"})".PadRight(14)): $($this.Message)`n"
        }
        return $str
    }

}