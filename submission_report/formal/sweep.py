import check_model as cm
# generalise: operation length L (dur in 1..L) ; rebuild explore with that range
def explore(P,mode,L):
    step=cm.make(P,mode)
    inits=[(0,0,a,b,d,0,0) for a in (False,True) for b in (False,True) for d in (False,True)]
    seen=set(inits); todo=list(inits); edges={}
    while todo:
        s=todo.pop(); es=[]
        for dur in range(1,L+1):
            outs,fl=step(s,dur,None)
            for o in outs:
                es.append((o,fl))
                if o not in seen: seen.add(o); todo.append(o)
        edges[s]=es
    return seen,edges
def cpu_starves(P,L):
    seen,edges=explore(P,'aging',L)
    W=[s for s in seen if s[2]]
    succ={s:[o for (o,fl) in edges[s] if not fl[0] and o[2]] for s in W}
    color={}
    for r in W:
        if r in color: continue
        st=[(r,iter(succ[r]))]; color[r]=1
        while st:
            u,it=st[-1]
            for v in it:
                if color.get(v)==1: return True
                if v not in color: color[v]=1; st.append((v,iter(succ[v]))); break
            else: color[u]=2; st.pop()
    return False
for L in (2,3,4,5):
    print('L=%d'%L,' P with starvation:',[P for P in range(1,11) if cpu_starves(P,L)])
