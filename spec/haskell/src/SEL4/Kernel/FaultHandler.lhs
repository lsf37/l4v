%
% Copyright 2014, General Dynamics C4 Systems
%
% This software may be distributed and modified according to the terms of
% the GNU General Public License version 2. Note that NO WARRANTY is provided.
% See "LICENSE_GPLv2.txt" for details.
%
% @TAG(GD_GPL)
%

This module contains functions that determine how recoverable faults encountered by user-level threads are propagated to the appropriate fault handlers.

> module SEL4.Kernel.FaultHandler (handleFault, handleTimeout, hasValidTimeoutHandler, isValidFaultHandler) where

\begin{impdetails}

% {-# BOOT-IMPORTS: SEL4.Machine SEL4.Model SEL4.Object.Structures SEL4.API.Failures #-}
% {-# BOOT-EXPORTS: handleFault handleTimeout isValidFaultHandler hasValidTimeoutHandler #-}

> import SEL4.API.Failures
> import SEL4.Machine
> import SEL4.Model
> import SEL4.Object
> import SEL4.Object.Structures(TCB(..), CTE(..))
> import {-# SOURCE #-} SEL4.Kernel.Thread

> import Data.Maybe(fromJust)

\end{impdetails}

> isValidFaultHandler :: Capability -> Bool
> isValidFaultHandler cap =
>     case cap of
>         EndpointCap _ _ True _ True -> True
>         NullCap -> True
>         _ -> False

> hasValidTimeoutHandler :: PPtr TCB -> Kernel Bool
> hasValidTimeoutHandler tptr = do
>     tcb <- getObject tptr
>     case cteCap (tcbTimeoutHandler tcb) of
>         EndpointCap {} -> return True
>         _ -> return False

\subsection{Handling Faults}

Faults generated by the "handleEvent" function (which is defined in \autoref{sec:api.syscall}) are caught and sent to "handleFault", defined below.

The parameters of this function are the fault and a pointer to the thread which requested the kernel operation that generated the fault.

> handleFault :: PPtr TCB -> Fault -> Kernel ()

When a thread faults, the kernel attempts to send a fault IPC to the fault handler endpoint. This has the side-effect of suspending the thread, placing it in the "BlockedOnFault" state until the recipient of the fault IPC replies to it. If the IPC fails, we call "handleDoubleFault" instead.

> handleFault tptr ex = do
>     tcb <- getObject tptr
>     hasFh <- sendFaultIPC tptr (cteCap (tcbFaultHandler tcb)) ex True `catchFailure` const (return False)
>     unless hasFh $ (handleNoFaultHandler tptr)

\subsection{Sending Fault IPC}

> handleTimeout :: PPtr TCB -> Fault -> Kernel ()
> handleTimeout tptr timeout = do
>     valid <- hasValidTimeoutHandler tptr
>     assert valid "no valid timeout handler"
>     tcb <- getObject tptr
>     sendFaultIPC tptr (cteCap (tcbTimeoutHandler tcb)) timeout False `catchFailure` const (return False)
>     return ()

If a thread causes a fault, then an IPC containing details of the fault is sent to a fault handler endpoint specified in the thread's TCB.

> sendFaultIPC :: PPtr TCB -> Capability -> Fault -> Bool -> KernelF Fault Bool
> sendFaultIPC tptr handlerCap fault canDonate = do
>     case handlerCap of

The kernel stores a copy of the fault in the thread's TCB, and performs an IPC send operation to the fault handler endpoint on behalf of the faulting thread. When the IPC completes, the fault will be retrieved from the TCB and sent instead of the message registers.

>         EndpointCap { capEPCanSend = True, capEPCanGrant = True,
>                       capEPCanGrantReply = canGrantReply } ->
>             withoutFailure $ do
>                 threadSet (\tcb -> tcb {tcbFault = Just fault}) tptr
>                 sendIPC True False (capEPBadge handlerCap)
>                     True canGrantReply canDonate tptr (capEPPtr handlerCap)
>                 return True
>         NullCap -> withoutFailure $ return False
>         _ -> fail "must be send+grant EPCap or NullCap"

\subsection{No Fault Handler}

> handleNoFaultHandler :: PPtr TCB -> Kernel ()
> handleNoFaultHandler tptr = setThreadState Inactive tptr

