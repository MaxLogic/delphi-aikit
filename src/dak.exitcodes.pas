unit Dak.ExitCodes;

interface

const
  cExitSuccess = 0;
  cExitUnhandledException = 1;
  cExitInvalidArgs = 2;
  cExitInvalidProjectInput = 3;
  // The same code reports a rejected analysis result: a failed gate or a failed verification.
  cExitRejectedResult = cExitInvalidProjectInput;
  cExitEnvironmentError = 4;
  cExitToolFailure = 6;
  cExitToolMissing = 7;

implementation

end.
