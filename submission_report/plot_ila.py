import csv, sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
plt.rcParams.update({'font.family':'serif','font.serif':['Liberation Serif','Times New Roman','DejaVu Serif'],
    'font.size':9,'axes.linewidth':0.8,'pdf.fonttype':42,'mathtext.fontset':'stix'})
T=500
def load(n):
    r=list(csv.reader(open(f'ila_cap{n}.csv')))
    h=[c.split('/')[-1].split('[')[0] for c in r[0]]
    return [dict(zip(h,x)) for x in r[2:]]
def col(R,k): return [x[k] for x in R]
def bit(R,k): return [int(v) for v in col(R,k)]
def hx(v): return v.lstrip('0') or '0'

def draw(name,R,lo,hi,panels,height_per=0.36):
    xs=list(range(lo-T,hi-T+1)); seg=R[lo:hi+1]
    fig,axs=plt.subplots(len(panels),1,sharex=True,figsize=(6.4,height_per*len(panels)+0.55))
    for ax,(label,kind,data) in zip(axs,panels):
        if kind=='bit':
            ax.step(xs,data(seg),where='post',lw=1.8,color='#1f4e9c'); ax.set_ylim(-0.25,1.35); ax.set_yticks([])
        else:   # bus: list of strings
            vals=data(seg); i=0
            while i<len(xs):
                j=i
                while j+1<len(xs) and vals[j+1]==vals[i]: j+=1
                x0,x1=xs[i],xs[j]+1; d=0.12
                ax.plot([x0,x0+d,x1-d,x1,x1-d,x0+d,x0],[0.5,1,1,0.5,0,0,0.5],lw=1.2,color='#1f4e9c')
                if vals[i]!='' and x1<=hi-T and (x1-x0)*0.26>=0.055*len(vals[i])+0.04: ax.text((x0+x1)/2,0.5,vals[i],ha='center',va='center',fontsize=6.5)
                i=j+1
            ax.set_ylim(-0.2,1.2); ax.set_yticks([])
        ax.set_ylabel(label,rotation=0,ha='right',va='center',fontsize=8.5)
        ax.grid(True,lw=0.4,color='0.8'); ax.axvline(0,color='#b22222',lw=1.0,ls='--')
        for s in ('top','right'): ax.spines[s].set_visible(False)
    axs[-1].set_xlim(lo-T,hi-T); axs[-1].set_xlabel('cycles from trigger (20 ns each)')
    from matplotlib.ticker import MultipleLocator
    axs[-1].xaxis.set_major_locator(MultipleLocator(2 if hi-lo<40 else 100))
    fig.subplots_adjust(left=0.2,right=0.985,top=0.99,bottom=0.5/(height_per*len(panels)+0.55)+0.02,hspace=0.18)
    fig.savefig(name+'.pdf'); plt.close(fig)

b=lambda k:(lambda s:[int(x[k]) for x in s])
h=lambda k:(lambda s:[hx(x[k]) for x in s])
opn=lambda s:[ {'00':'RD','01':'WR','10':'SC','11':'INJ'}[x['c_req_op']] if x['c_req_valid']=='1' else '' for x in s]

# A: single error, B: double error  (samples 495..515)
for n,evk in (('A','ev_ce'),('B','ev_ue')):
    R=load(n)
    draw('plot_cap'+n,R,495,515,[
        ('ev_valid','bit',b('ev_valid')),(evk,'bit',b(evk)),
        ('ev_syn','bus',h('ev_syn')),('ev_addr','bus',h('ev_addr')),
        ('m_rsp_err','bit',b('m_rsp_err')),('if_id_pc','bus',h('if_id_pc'))])
# D: injection
R=load('D')
draw('plot_capD',R,495,515,[
    ('c_req_valid','bit',b('c_req_valid')),('c_req_op','bus',opn),('c_req_ready','bit',b('c_req_ready')),
    ('m_req_valid','bit',b('m_req_valid')),('m_req_ready','bit',b('m_req_ready')),('ij_count','bus',h('ij_count'))])
# C2: CPU wait
R=load('C2')
draw('plot_capC2',R,490,510,[
    ('m_req_valid','bit',b('m_req_valid')),('m_req_ready','bit',b('m_req_ready')),
    ('c_req_valid','bit',b('c_req_valid')),('c_req_op','bus',opn),('c_req_ready','bit',b('c_req_ready'))])
# C: scrub spacing, samples 280..1130 (pulses)
R=load('C')
sc=lambda s:[1 if (x['c_req_valid']=='1' and x['c_req_op']=='10') else 0 for x in s]
rd=lambda s:[1 if (x['c_req_valid']=='1' and x['c_req_op']=='00') else 0 for x in s]
wr=lambda s:[1 if (x['c_req_valid']=='1' and x['c_req_op']=='01') else 0 for x in s]
draw('plot_capC',R,280,1130,[('scrub op','bit',sc),('CPU read','bit',rd),('CPU write','bit',wr)])
