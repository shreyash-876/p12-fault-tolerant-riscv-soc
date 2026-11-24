# Explicit-state re-check of the arbiter model (independent of NuSMV).
import sys, itertools
def make(P, mode):
    # mode: 'aging' (step3/4/5a), 'noaging' (step2), 'bgprio' (step5b)
    def step(s, dur, nreq):
        st,left,c,sr,ir,sc,ic = s
        ready = left==0; rsp = left==1
        sa = sr and (sc>=P) if mode!='noaging' else False
        ia = ir and (ic>=P) if mode!='noaging' else False
        ps = sr and (not ir or (sa and not ia))
        pi = ir and not ps
        if mode=='aging':   gbg = st==0 and (sr or ir) and (not c or sa or ia)
        elif mode=='bgprio':gbg = st==0 and (sr or ir)
        else:               gbg = st==0 and (sr or ir) and not c
        gi, gs = gbg and pi, gbg and ps
        gc = st==0 and c and not gbg
        cr, ir_, sr_ = gc and ready, gi and ready, gs and ready
        acc = cr or ir_ or sr_
        ns = 1 if cr else 2 if sr_ else 3 if ir_ else (0 if (st!=0 and rsp) else st)  # 0 IDLE 1 CPU 2 SCR 3 INJ
        nl = dur if acc else (left-1 if left>0 else 0)
        nsc = 0 if (not sr or sr_) else min(sc+1,P)
        nic = 0 if (not ir or ir_) else min(ic+1,P)
        def nr(req, rdy, mine):
            if req and not rdy: return (True,)
            if rdy: return (False,)
            if st==mine and not rsp: return (False,)
            return (False,True)
        outs=[]
        for a in nr(c,cr,1):
            for b in nr(sr,sr_,2):
                for d in nr(ir,ir_,3):
                    outs.append((ns,nl,a,b,d,nsc,nic))
        return outs, (cr,sr_,ir_,acc)
    return step
def explore(P,mode):
    step=make(P,mode); init=(0,0,False,False,False,0,0)
    # initial requests are free (init(cpu_req) unconstrained in NuSMV)
    inits=[(0,0,a,b,d,0,0) for a in (False,True) for b in (False,True) for d in (False,True)]
    seen=set(inits); todo=list(inits); edges={}
    while todo:
        s=todo.pop(); es=[]
        for dur in (1,2,3):
            outs,fl=step(s,dur,None)
            for o in outs:
                es.append((o,fl))
                if o not in seen: seen.add(o); todo.append(o)
        edges[s]=es
    return seen,edges
def analyse(P,mode):
    seen,edges=explore(P,mode)
    res={'states':len(seen)}
    # safety: at most one ready (by construction) ; accept implies IDLE & left==0
    # liveness / wait bound for each requester: waiting subgraph = states where req true and not ready
    for name,idx_req,idx_rdy in (('cpu',2,0),('scr',3,1),('inj',4,2)):
        W=[s for s in seen if s[idx_req]]
        # edge s->o stays "waiting" if the grant flag for this requester is false in s
        succ={s:[o for (o,fl) in edges[s] if not fl[idx_rdy] and o[idx_req]] for s in W}
        # starving iff cycle in succ (reachable by construction)
        color={}; cyc=False
        sys.setrecursionlimit(10**6)
        # iterative DFS for cycle + longest path
        longest={}
        stack=[]
        for r in W:
            if r in color: continue
            stack=[(r,iter(succ[r]))]; color[r]=1
            while stack:
                u,it=stack[-1]
                for v in it:
                    if color.get(v)==1: cyc=True; break
                    if v not in color:
                        color[v]=1; stack.append((v,iter(succ[v]))); break
                else:
                    color[u]=2; stack.pop()
                    longest[u]=1+max([longest[v] for v in succ[u]],default=0) if not cyc else 0
                if cyc: break
            if cyc: break
        # wait cycles = number of cycles with req && !ready = longest waiting path (counted in states)
        res[name]= 'STARVES' if cyc else max(longest.values())
    return res
if __name__=='__main__':
    for P,mode in [(20,'aging'),(5,'aging'),(4,'aging'),(3,'aging'),(20,'noaging'),(20,'bgprio'),(256,'aging')]:
        print(P,mode,analyse(P,mode),flush=True)
