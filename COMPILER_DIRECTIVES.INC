{.$DEFINE TRACEDEBUG}          // save debug log

{$IFDEF TRACEDEBUG}
  {.$DEFINE TRACEDEBUGMEMORY}   // save debug log to memory and only write it to disk on exit.
  {.$DEFINE SCOREDEBUG}         // save debug information on incoming scores
{$ENDIF}

