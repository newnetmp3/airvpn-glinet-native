(function(){
'use strict';
window.__AIRVPN_UI_VERSION__='0.11.10';
function installStylesheet(){
  var id='airvpn-native-stylesheet';
  var current=document.getElementById(id);
  var href='/airvpn-native-ui.css?v='+encodeURIComponent(window.__AIRVPN_UI_VERSION__);
  if(current&&current.getAttribute('href')===href)return;
  if(current)current.remove();
  var link=document.createElement('link');
  link.id=id;
  link.rel='stylesheet';
  link.href=href;
  document.head.appendChild(link);
}
installStylesheet();
var A=window.__airvpn491=window.__airvpn491||{id:49100,mode:false};
function rpc(m,a){
var h={'Content-Type':'application/json','glinet':'1'};
A.debug=A.debug||{};
A.debug.transport='cgi-bridge';
A.debug.authMode='native-same-origin-cookie';
return fetch('/cgi-bin/airvpn-native',{
method:'POST',
credentials:'same-origin',
cache:'no-store',
headers:h,
body:JSON.stringify({method:m,args_json:JSON.stringify(a||{})})
}).then(function(r){
  return r.text().then(function(raw){
    var j;
    try{j=raw?JSON.parse(raw):{}}catch(parseErr){
      var preview=String(raw||'').replace(/\s+/g,' ').trim().slice(0,1200);
      var ep=Error('AirVPN bridge returned a non-JSON response (HTTP '+r.status+').'+(preview?' Raw response: '+preview:''));
      ep.code='NON_JSON';ep.httpStatus=r.status;ep.output=raw||'';throw ep;
    }
    if(j&&j.ok===false){var e0=Error(j.error||j.output||('Bridge error '+(j.code||'')));e0.code=j.code;e0.output=j.output||'';throw e0}
    if(j&&j.error){var e1=Error(j.error.message||j.error||JSON.stringify(j));e1.code=j.code;e1.output=j.output||'';throw e1}
    // rpcd wrappers report command failures through the returned code.
    if(j&&typeof j.code==='number'&&j.code!==0){var e2=Error(j.output||('AirVPN command failed with code '+j.code));e2.code=j.code;e2.output=j.output||'';throw e2}
    return j||{};
  });
})
}
function T(e){return(e.textContent||'').trim()}function E(s){return String(s==null?'':s).replace(/[&<>\"']/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]})}
function normText(e){return (e&&e.textContent||'').replace(/\s+/g,' ').trim()}
var AV_SIDEBAR_ACTIVE_KEY='airvpn-native-sidebar-active';
function rememberAirVPNOpen(on){
  A.sidebarPreferred=!!on;
  try{
    if(on)sessionStorage.setItem(AV_SIDEBAR_ACTIVE_KEY,'1');
    else sessionStorage.removeItem(AV_SIDEBAR_ACTIVE_KEY);
    // Migrate the old provider-tab session flag.
    sessionStorage.removeItem('airvpn-native-provider');
  }catch(_){}
}
function wantsAirVPN(){
  if(typeof A.sidebarPreferred==='boolean')return A.sidebarPreferred;
  try{
    var current=sessionStorage.getItem(AV_SIDEBAR_ACTIVE_KEY)==='1';
    var legacy=sessionStorage.getItem('airvpn-native-provider')==='airvpn';
    A.sidebarPreferred=current||legacy;
    if(legacy){sessionStorage.setItem(AV_SIDEBAR_ACTIVE_KEY,'1');sessionStorage.removeItem('airvpn-native-provider')}
  }catch(_){A.sidebarPreferred=false}
  return !!A.sidebarPreferred;
}
function isVisible(e){
  if(!e || !e.getBoundingClientRect)return false;
  var r=e.getBoundingClientRect(), st=getComputedStyle(e);
  return r.width>1 && r.height>1 && st.display!=='none' && st.visibility!=='hidden';
}
function exactTextCandidates(txt){
  var all=document.querySelectorAll('body *'), out=[], needle=txt.toLowerCase();
  for(var i=0;i<all.length;i++){
    var e=all[i],tag=(e.tagName||'').toLowerCase();
    if(tag==='script'||tag==='style'||tag==='noscript')continue;
    var t=normText(e);
    // Collapsed VPN submenu rows remain in the DOM on GL.iNet 4.9.1.
    if(t && t.length<=64 && t.toLowerCase()===needle)out.push(e);
  }
  return out;
}
function menuContextScore(item){
  var score=0,cur=item;
  for(var i=0;i<9&&cur;i++,cur=cur.parentElement){
    if(cur===document.body||cur===document.documentElement)break;
    var tag=(cur.tagName||'').toLowerCase();
    var role=(cur.getAttribute&&cur.getAttribute('role'))||'';
    var cls=String(cur.className||'');
    var id=String(cur.id||'');
    if(tag==='nav'||tag==='aside')score+=80;
    if(tag==='ul'||tag==='ol')score+=12;
    if(role==='menu'||role==='navigation')score+=60;
    if(role==='menuitem')score+=35;
    if(/(^|[-_ ])(?:side(?:bar)?|menu|nav)(?:[-_ ]|$)/i.test(cls+' '+id))score+=45;
    if(/el-menu|submenu|menu-item|nav-item|sidebar/i.test(cls))score+=55;
  }
  return score;
}
function nativeSidebarItemForLabel(label){
  var cands=exactTextCandidates(label), vw=window.innerWidth||document.documentElement.clientWidth||1280;
  var best=null,bestScore=1e9;
  cands.forEach(function(labelEl){
    var cur=labelEl,item=null,anchor=null;
    for(var n=0;n<8&&cur;n++,cur=cur.parentElement){
      if(cur===document.body||cur===document.documentElement)break;
      var tag=(cur.tagName||'').toLowerCase(), role=(cur.getAttribute&&cur.getAttribute('role'))||'', cls=String(cur.className||'');
      if(tag==='a'&&!anchor)anchor=cur;
      if(tag==='li'||role==='menuitem'||/el-menu-item|menu-item|submenu-item|nav-item/i.test(cls)){item=cur;break}
    }
    item=item||anchor;
    if(!item)return;

    var visible=isVisible(item), context=menuContextScore(item);
    var r=item.getBoundingClientRect?item.getBoundingClientRect():{left:9999,top:9999,width:0,height:0};

    if(visible){
      // Validate the row by size and menu ancestry, not viewport X position.
      if(r.width<72||r.width>430||r.height<24||r.height>86)return;
      if(context<70)return;
      if(r.right<0||r.left>vw)return;
      var score=Math.abs(r.width-220)+r.top*.01-Math.min(context,220)*8;
      if(score<bestScore){best={item:item,labelEl:labelEl,label:label,visible:true,contextScore:context};bestScore=score}
      return;
    }

    // Hidden submenu rows are valid only with strong menu ancestry.
    if(context<70)return;
    var hiddenScore=5000-Math.min(context,300)*10;
    if(hiddenScore<bestScore){best={item:item,labelEl:labelEl,label:label,visible:false,contextScore:context};bestScore=hiddenScore}
  });
  return best;
}
function sidebarReference(){
  // Insert beside the native VPN pages.
  var labels=['VPN Client Profile','VPN Dashboard','VPN Client'];
  for(var i=0;i<labels.length;i++){
    var r=nativeSidebarItemForLabel(labels[i]);
    if(r)return r;
  }
  return null;
}
function sidebarContainer(item){
  if(!item)return null;
  var vh=window.innerHeight||720, vw=window.innerWidth||1280;
  var cur=item,best=null,bestScore=-1e9;
  // Walk far enough to reach the primary navigation rail.
  for(var i=0;i<28&&cur;i++,cur=cur.parentElement){
    if(cur===document.body||cur===document.documentElement)break;
    if(!cur.getBoundingClientRect)continue;
    var r=cur.getBoundingClientRect(), cls=String(cur.className||''), id=String(cur.id||'');
    if(r.width<90||r.width>430||r.height<Math.min(380,vh*.50))continue;
    if(r.right<0||r.left>vw)continue;
    var semantic=/el-menu|sidebar|side-bar|sidemenu|side-menu|navigation|(^|[-_ ])nav([-_ ]|$)/i.test(cls+' '+id)?220:0;
    // Prefer tall, top-aligned ancestors over nested submenu wrappers.
    var score=r.height*3-r.top*8+semantic-Math.abs(r.width-180)*.5;
    if(score>bestScore){best=cur;bestScore=score}
  }
  return best||item.parentElement;
}
function primarySidebarContainer(fallbackItem){
  // Top-level labels identify the full-height navigation rail.
  var labels=['INTERNET','WIRELESS','CLIENTS','NETWORK','SYSTEM'];
  for(var i=0;i<labels.length;i++){
    var ref=nativeSidebarItemForLabel(labels[i]);
    if(ref&&ref.item&&ref.visible!==false){
      var side=sidebarContainer(ref.item);
      if(side&&side.getBoundingClientRect){
        var r=side.getBoundingClientRect();
        if(r.height>=Math.min(380,(window.innerHeight||720)*.50))return side;
      }
    }
  }
  return sidebarContainer(fallbackItem);
}
function adminHeaderBounds(){
  var all=document.querySelectorAll('body *'), vw=window.innerWidth||1280;
  var best=null,bestScore=-1e9;
  for(var i=0;i<all.length;i++){
    var el=all[i],t=normText(el);
    if(!t||t.length>48||!/^Admin Panel(?:\s+v?[0-9][0-9.\-a-z]*)?$/i.test(t))continue;
    if(!isVisible(el))continue;
    var cur=el;
    for(var n=0;n<10&&cur;n++,cur=cur.parentElement){
      if(cur===document.body||cur===document.documentElement)break;
      if(!cur.getBoundingClientRect)continue;
      var r=cur.getBoundingClientRect();
      if(r.width<420||r.width>vw+4||r.height<28||r.height>115)continue;
      if(r.top<-4||r.top>90)continue;
      // The widest short top bar defines the application shell bounds.
      var score=r.width-r.height*2-r.top*2;
      if(score>bestScore){best=cur;bestScore=score}
    }
  }
  if(!best)return null;
  var r=best.getBoundingClientRect();
  return {left:r.left,top:r.top,right:r.right,bottom:r.bottom,width:r.width,height:r.height};
}
function appShellRight(side){
  if(!side||!side.getBoundingClientRect)return null;
  var sr=side.getBoundingClientRect(), vw=window.innerWidth||1280;
  var cur=side.parentElement,best=null,bestWidth=1e9;
  for(var i=0;i<20&&cur;i++,cur=cur.parentElement){
    if(cur===document.body||cur===document.documentElement)break;
    if(!cur.getBoundingClientRect)continue;
    var r=cur.getBoundingClientRect();
    if(r.width<sr.width+420||r.width>vw+4)continue;
    if(r.right<sr.right+320)continue;
    if(r.left>sr.left+8)continue;
    if(r.height<Math.min(420,(window.innerHeight||720)*.55))continue;
    if(r.width<bestWidth){best=r;bestWidth=r.width}
  }
  return best?best.right:null;
}
function clearNativeActiveState(node){
  if(!node||node.nodeType!==1)return;
  var clean=function(el){
    if(!el||el.nodeType!==1)return;
    if(el.classList)['is-active','active','selected','router-link-active','router-link-exact-active'].forEach(function(c){el.classList.remove(c)});
    el.removeAttribute('aria-current');
    el.removeAttribute('data-active');
  };
  clean(node);Array.prototype.forEach.call(node.querySelectorAll('*'),clean);
}
function replaceSidebarLabel(clone,sourceLabel){
  var needle=String(sourceLabel||'').toLowerCase(), nodes=clone.querySelectorAll('*');
  for(var i=0;i<nodes.length;i++){
    var el=nodes[i],txt=normText(el);
    if(txt.toLowerCase()!==needle)continue;
    var childExact=false;
    for(var j=0;j<el.children.length;j++)if(normText(el.children[j]).toLowerCase()===needle){childExact=true;break}
    if(!childExact){el.textContent='AirVPN';return}
  }
  clone.textContent='AirVPN';
}
function markSidebarActive(on){
  var item=document.getElementById('airvpn-sidebar-item');
  if(!item)return;
  if(on)item.setAttribute('data-airvpn-active','1');else item.removeAttribute('data-airvpn-active');
}
function syncSidebarRowPlacement(item,ref){
  if(!item||!ref||!ref.item||!ref.item.parentElement)return;
  var parent=ref.item.parentElement;
  if(item.parentElement!==parent){
    if(item.parentElement)item.remove();
    parent.insertBefore(item,ref.item.nextSibling);
  }else if(ref.item.nextSibling!==item){
    parent.insertBefore(item,ref.item.nextSibling);
  }
  // Mirror direct row visibility when firmware applies it to the submenu item.
  item.style.display=ref.item.style.display||'';
  item.style.visibility=ref.item.style.visibility||'';
}
function installSidebarItem(ref){
  if(!ref||!ref.item||!ref.item.parentElement)return null;
  var old=document.getElementById('airvpn-sidebar-item');
  if(old&&old.parentElement===ref.item.parentElement){
    syncSidebarRowPlacement(old,ref);
    A.sidebarItem=old;
    A.sidebarRoot=sidebarContainer(old);
    A.debug=A.debug||{};A.debug.sidebarAnchor=ref.label;A.debug.sidebarAnchorVisible=ref.visible!==false;A.debug.sidebarAnchorContext=ref.contextScore||0;A.debug.sidebarInstalled=true;
    return old;
  }
  if(old)old.remove();
  var item=ref.item.cloneNode(true);
  item.id='airvpn-sidebar-item';
  item.setAttribute('data-airvpn-native-entry','1');
  item.setAttribute('title','AirVPN');
  clearNativeActiveState(item);
  replaceSidebarLabel(item,ref.label);
  var links=[];if((item.tagName||'').toLowerCase()==='a')links.push(item);
  links=links.concat(Array.prototype.slice.call(item.querySelectorAll('a')));
  links.forEach(function(a){a.removeAttribute('href');a.removeAttribute('target');a.setAttribute('role','button');a.setAttribute('tabindex','0')});
  item.addEventListener('click',function(ev){
    ev.preventDefault();ev.stopPropagation();if(ev.stopImmediatePropagation)ev.stopImmediatePropagation();
    showAirSidebar(item);return false;
  },true);
  item.addEventListener('keydown',function(ev){
    if(ev.key==='Enter'||ev.key===' '){ev.preventDefault();showAirSidebar(item)}
  },true);
  ref.item.parentElement.insertBefore(item,ref.item.nextSibling);
  syncSidebarRowPlacement(item,ref);
  A.sidebarItem=item;
  A.sidebarRoot=sidebarContainer(item);
  A.debug=A.debug||{};A.debug.sidebarAnchor=ref.label;A.debug.sidebarAnchorVisible=ref.visible!==false;A.debug.sidebarAnchorContext=ref.contextScore||0;A.debug.sidebarInstalled=true;
  if(A.mode)markSidebarActive(true);
  return item;
}
function sidebarBounds(item){
  var side=primarySidebarContainer(item), r=side&&side.getBoundingClientRect?side.getBoundingClientRect():null;
  var vw=window.innerWidth||document.documentElement.clientWidth||1280;
  var vh=window.innerHeight||document.documentElement.clientHeight||720;
  var ir=item&&item.getBoundingClientRect?item.getBoundingClientRect():{right:240,top:0};
  var left=(r&&r.width>=40&&r.width<=500)?r.right:(ir.right||240);
  var header=adminHeaderBounds();
  var top=header?header.bottom:((r&&r.height>100)?r.top:0);
  var right=(header&&header.right>left+320)?header.right:appShellRight(side);
  if(!(right>left+320))right=vw;
  left=Math.max(72,left);top=Math.max(0,top);right=Math.min(vw,Math.max(left+320,right));
  A.debug=A.debug||{};
  A.debug.primarySidebarBounds=r?{left:r.left,top:r.top,right:r.right,bottom:r.bottom,width:r.width,height:r.height}:null;
  A.debug.adminHeaderBounds=header;
  A.debug.airvpnPageBounds={left:left,top:top,right:right,bottom:vh,width:right-left,height:vh-top};
  return {left:left,top:top,right:right,bottom:vh};
}
function positionAirSidebarView(){
  var view=document.getElementById('airvpn-sidebar-view'), item=document.getElementById('airvpn-sidebar-item');
  if(!view||!item)return;
  var b=sidebarBounds(item);
  view.style.left=Math.round(b.left)+'px';
  view.style.top=Math.round(b.top)+'px';
  view.style.width=Math.max(320,Math.round(b.right-b.left))+'px';
  view.style.height=Math.max(240,Math.round(b.bottom-b.top))+'px';
}
function buildAirPanel(panel){
  if(!panel)return Promise.reject(new Error('AirVPN panel host is unavailable'));
  panel.innerHTML='<div class="avloading">Loading AirVPN…</div>';
  return Promise.all([rpc('get_config'),rpc('api_key_status'),rpc('cache_status')])
    .then(function(r){
      render(panel,r[0]||{},r[1]||{},r[2]||{});
      A.debug=A.debug||{};A.debug.panelRendered=true;
      return panel;
    })
    .catch(function(e){
      A.debug=A.debug||{};A.debug.rpcError=String(e&&e.message||e);
      panel.innerHTML='<div class="avmsg">AirVPN UI error: '+E(e&&e.message||String(e))+'<br>Reload this page after signing in if needed.</div>';
      return panel;
    });
}
function cleanupAirRuntime(){
  A.viewToken=(A.viewToken||0)+1;
  A.latencyRunToken=(A.latencyRunToken||0)+1;
  A.catalogLoadToken=(A.catalogLoadToken||0)+1;
  A.latencyTesting=false;A.catalogLoading=null;
  if(A.catalogProgressTimer){clearInterval(A.catalogProgressTimer);A.catalogProgressTimer=null}
  stopVpnPowerPolling();
  if(A.documentPointerHandler){try{document.removeEventListener('pointerdown',A.documentPointerHandler,true)}catch(_){}A.documentPointerHandler=null}
  if(A.tableResizeObserver){try{A.tableResizeObserver.disconnect()}catch(_){}A.tableResizeObserver=null}
  var modal=document.getElementById('av-server-modal');if(modal)modal.remove();
  closeSelectMenus();
}
function restore(clearPreference){
  A.mode=false;
  cleanupAirRuntime();
  var view=document.getElementById('airvpn-sidebar-view');if(view)view.remove();
  markSidebarActive(false);
  if(clearPreference!==false)rememberAirVPNOpen(false);
}
function showAirSidebar(item){
  rememberAirVPNOpen(true);
  if(A.mode&&document.getElementById('airvpn-sidebar-view')){positionAirSidebarView();markSidebarActive(true);return}
  cleanupAirRuntime();
  A.mode=true;A.airvpnBaseHash=location.hash;markSidebarActive(true);
  var old=document.getElementById('airvpn-sidebar-view');if(old)old.remove();
  var view=document.createElement('div');view.id='airvpn-sidebar-view';view.className='airvpn-sidebar-page';
  var panel=document.createElement('div');panel.id='airvpn-provider-view';panel.className='avpanel av-sidebar-panel';
  panel.innerHTML='<div class="avloading">Loading AirVPN…</div>';
  view.appendChild(panel);document.body.appendChild(view);positionAirSidebarView();
  buildAirPanel(panel);
  A.debug=A.debug||{};A.debug.sidebarView=true;
}
function sidebarNavigationCapture(ev){
  if(!A.mode)return;
  var item=document.getElementById('airvpn-sidebar-item');
  if(item&&item.contains(ev.target))return;
  var root=A.sidebarRoot||sidebarContainer(item);
  if(root&&root.contains(ev.target))restore(true);
}
function row(l,h){return '<div class="avrow"><label>'+E(l)+'</label><div>'+h+'</div></div>'}function sel(id,items,v){return'<select id="'+id+'">'+items.map(function(x){return'<option value="'+E(x[0])+'" '+(String(x[0])===String(v)?'selected':'')+'>'+E(x[1])+'</option>'}).join('')+'</select>'}
function v(id){var x=document.getElementById(id);return x?x.value:''}function c(id){var x=document.getElementById(id);return!!(x&&x.checked)}
function setSortApplyEnabled(enabled){
  var b=document.getElementById('avsortapply');
  if(!b)return;
  b.disabled=!enabled;
  b.classList.toggle('disabled',!enabled);
  b.setAttribute('aria-disabled',enabled?'false':'true');
}
function markSortDirty(){
  setSortApplyEnabled(true);
}
function setVpnPowerButton(state){
  var b=document.getElementById('avvpnpower');if(!b)return;
  var on=!!(state&&state.on),mapped=Number(state&&state.mapped)||0,profiles=Number(state&&state.profiles)||0;
  b.dataset.on=on?'1':'0';
  b.dataset.mapped=String(mapped);
  b.dataset.profiles=String(profiles);
  b.textContent=on?'Turn VPN Off':'Turn VPN On';
  b.classList.toggle('on',on);
  b.classList.toggle('off',!on);
  // Keep this clickable so an empty-profile state can explain itself.
  b.disabled=false;
  b.setAttribute('aria-disabled','false');
  var notice=document.getElementById('avpowernotice');
  if(profiles<1)b.title='No AirVPN VPN profiles are available to activate';
  else {
    if(notice)notice.textContent='';
    if(mapped<1)b.title='Create and enable the VPN Dashboard tunnel for the current AirVPN profile';
    else b.title=on?'Disable the mapped AirVPN tunnel':'Enable the mapped AirVPN tunnel';
  }
}
function refreshVpnPower(){
  if(A.vpnPowerRefreshBusy)return Promise.resolve(null);
  A.vpnPowerRefreshBusy=true;
  return rpc('vpn_power_status',{}).then(function(r){
    var data=r&&r.output;
    if(typeof data==='string'){try{data=JSON.parse(data)}catch(_){data={}}}
    setVpnPowerButton(data||{});
    if(data&&data.selector){A.selectedServer=String(data.selector);if(A.catalogRows&&A.catalogRows.length)makeServerTable('avcatalogtable',A.catalogRows,true);}
    return data;
  }).catch(function(){
    setVpnPowerButton({mapped:0,on:false});
    return null;
  }).finally(function(){
    A.vpnPowerRefreshBusy=false;
  });
}
function stopVpnPowerPolling(){
  if(A.vpnPowerPollTimer){clearInterval(A.vpnPowerPollTimer);A.vpnPowerPollTimer=null;}
}
function startVpnPowerPolling(){
  stopVpnPowerPolling();
  refreshVpnPower();
  A.vpnPowerPollTimer=setInterval(function(){
    if(A.activeAirTab==='browser')refreshVpnPower();
  },5000);
}
function render(p,x,k,cache){
  var setupOk=!!(k&&k.configured&&x&&x.device&&x.protocol&&x.ip_layer);
  var firstTab=setupOk?(A.activeAirTab||'browser'):'settings';
  p.innerHTML=
  '<div class="avhead"><div><h2>AirVPN</h2><div class="muted">Generate and manage AirVPN profiles through the native GL.iNet VPN client backend.</div></div><span class="pill">WireGuard</span></div>'+
  '<div class="avsubtabs" role="tablist" aria-label="AirVPN sections">'+
    '<button type="button" class="avsubtab" data-avtab="browser" role="tab">Server Browser</button>'+
    '<button type="button" class="avsubtab" data-avtab="settings" role="tab">Settings</button>'+
    '<button type="button" class="avsubtab" data-avtab="diagnostics" role="tab">Diagnostics</button>'+
  '</div>'+
  '<div class="avtabpane" data-avpane="browser" role="tabpanel">'+
    '<div class="avcatalog avcatalog-primary"><div class="avcatalog-head"><div><strong>AirVPN Server Browser</strong><div class="muted">Browse cached servers, compare remaining capacity, and select an AirVPN host.</div></div>'+
    '<div class="avbrowser-power"><button type="button" id="avvpnpower" class="avvpnpower" data-a="vpn-power">VPN</button><div id="avpowernotice" class="avpowernotice" role="status" aria-live="polite"></div></div>'+
    '<div class="avcatalog-controls"><select id="avcatalogcountry"><option value="ALL">All</option>'+AV_KNOWN_COUNTRIES.map(function(x){return '<option value="'+E(x[0])+'">'+E(x[1]+' ('+x[0]+')')+'</option>'}).join('')+'</select><button data-a="catalog">Download Servers</button><button class="secondary" data-a="best">Best Server</button><button class="secondary" data-a="latency">Test Top Latency</button><button class="secondary" data-a="latency-all">Test All Latency</button></div></div>'+
    '<div class="avbrowser-sort"><label>Sort by '+sel('avsort',[['smart_rank','Smart Rank'],['available_bandwidth','Available bandwidth (Max - Current)'],['max_bandwidth','Maximum bandwidth'],['name','Server name'],['country','Country'],['city','City / location'],['score','Score'],['load','Load'],['bandwidth','Current bandwidth'],['effective_bandwidth','Effective bandwidth'],['users','Users'],['health','Health'],['entry_ip','Entry IP']],x.sort_column||'smart_rank')+'</label>'+
    '<label>Direction '+sel('avdir',[['asc','Ascending'],['desc','Descending']],x.sort_direction||'desc')+'</label>'+
    '<button type="button" id="avsortapply" class="avsortapply" data-a="apply-sort">Apply</button>'+
    '<details class="avcolumns"><summary>Column Options</summary><div class="avcolumnmenu">'+
      AV_DEFAULT_COLUMN_ORDER.map(function(k){var m=AV_COLUMN_META[k];if(k==='name')return '<label class="avcolumnlocked"><input type="checkbox" checked disabled> '+E(m.label)+' <small>(pinned)</small></label>';return '<label><input type="checkbox" data-avcolumn="'+k+'"> '+E(m.label)+'</label>'}).join('')+
      '<div class="avcolumnmenu-actions"><button type="button" class="avsortapply" data-a="apply-columns">Apply</button><button type="button" class="secondary avresetcolumns" data-a="reset-columns">Reset</button></div>'+
    '</div></details>'+
    '<button type="button" id="avfitcolumns" class="avsortapply avfitcolumns" data-a="fit-columns">'+(A.fitColumns?'Show All Columns':'Fit Columns')+'</button></div>'+
    '<div id="avcatalogmeta" class="muted">Loading cached server catalog…</div>'+
    '<div id="avprofileprogress" class="avdiagprogress" hidden aria-live="polite"><div class="avdiagprogresshead"><span id="avprofilestage">Preparing…</span><strong id="avprofilepct">0%</strong></div><div class="avdiagprogressrail" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><div class="avdiagprogressbar"></div></div><div id="avprofileelapsed" class="muted">Elapsed: 0s</div></div>'+
    '<div id="avcatalogprogress" class="avprogress" aria-live="polite" aria-label="Server download progress"><div class="avprogressbar"></div></div>'+
    '<section id="avlatencydialog" class="avlatencydialog" hidden aria-live="polite" aria-label="Latency test progress">'+
      '<div class="avlatencytop"><div><strong id="avlatencytitle">Testing latency</strong><div id="avlatencystatus" class="muted">Preparing…</div></div></div>'+
      '<div class="avlatencymodes" role="group" aria-label="Latency progress verbosity"><button type="button" class="active" data-a="latency-basic">Basic</button><button type="button" data-a="latency-details">Show Details</button></div>'+
      '<div class="avlatencycurrent"><span id="avlatencycurrent">Preparing server list…</span><strong id="avlatencycount">0 / 0</strong></div>'+
      '<div class="avlatencyprogress" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><div class="avlatencyprogressbar"></div></div>'+
      '<div id="avlatencypercent" class="avlatencypercent">0%</div>'+
      '<div id="avlatencydetails" class="avlatencydetails" hidden><div class="avlatencydetailshead"><span>Server</span><span>Country</span><span>Host</span><span>Result</span></div><div id="avlatencylog" class="avlatencylog"></div></div>'+
    '</section>'+
    '<div id="avcatalogtable"></div></div>'+
  '</div>'+
  '<div class="avtabpane" data-avpane="settings" role="tabpanel">'+
    '<div class="avgrid">'+
      row('API key','<input id="ava" type="password" autocomplete="new-password" autocapitalize="off" spellcheck="false" data-lpignore="true" data-1p-ignore="true" placeholder="'+(k.configured?'Saved — enter only to replace':'Paste AirVPN API key')+'"><small id="avkeystatus">'+E(k.configured?('Saved in '+(k.storage==='uci'?'OpenWrt UCI':'legacy storage')+(k.validated?' — validated by AirVPN':' — validation pending')):'No API key saved')+'</small><small>Keys are validated against AirVPN before replacement. The key itself is never returned to the browser after saving.</small>')+
      row('AirVPN device name / ID','<div class="avinline"><input id="avd" list="avdevlist" value="'+E(x.device||'default')+'"><button type="button" class="secondary" data-a="detect-devices">Detect Devices</button></div><datalist id="avdevlist"></datalist><small id="avdevstatus">Use Detect Devices to query the devices registered to this AirVPN account.</small>')+
      row('Countries / selectors','<textarea id="avs">'+E(x.selectors||'earth')+'</textarea><small>Friendly names supported: Canada, United States, Netherlands, Germany, etc.</small>')+
      row('Preferred WireGuard port',sel('avp',[['wireguard_1_udp_1637','UDP 1637'],['wireguard_1_udp_47107','UDP 47107'],['wireguard_1_udp_51820','UDP 51820']],x.protocol||'wireguard_1_udp_1637'))+
      row('Entry IP layer',sel('avl',[['ipv4','IPv4'],['ipv6','IPv6']],x.ip_layer||'ipv4'))+
      row('Endpoint resolution',sel('avr',[['off','Keep hostname / generator default'],['on','Resolve endpoint to IP']],x.resolve||'off'))+
      row('Server discovery','<input id="avdisc" type="checkbox" '+(x.use_server_discovery!==false?'checked':'')+'>')+
      row('Healthy / available only','<input id="avh" type="checkbox" '+(x.health_only!==false?'checked':'')+'>')+
      row('Minimum score','<input id="avmin" value="'+E(x.min_score||'0')+'">')+
      row('Maximum load','<input id="avmax" value="'+E(x.max_load||'100')+'">')+
      row('Force country code','<input id="avcc" placeholder="US, CA, NL…" value="'+E(x.country_filter||'')+'">')+
      row('Include server regex','<input id="avinc" value="'+E(x.include_server||'')+'">')+
      row('Exclude server regex','<input id="avexc" value="'+E(x.exclude_server||'')+'">')+
      row('Favorite servers','<textarea id="avfav">'+E(x.favorites||'')+'</textarea><small>Comma-separated; favorites receive a Smart Rank bonus.</small>')+
      row('Excluded servers','<textarea id="avsex">'+E(x.server_exclusions||'')+'</textarea><small>Comma-separated exact server names.</small>')+
      row('Latency candidates','<input id="avlatn" value="'+E(x.latency_candidates||'12')+'"><small>Top candidates tested only when requested.</small>')+      '<input type="hidden" id="avcolorder" value="'+E((x.column_order||AV_DEFAULT_COLUMN_ORDER.join(',')))+'">'+      '<input type="hidden" id="avhiddencols" value="'+E(x.hidden_columns||'')+'">'+
      row('MTU','<input id="avmtu" value="'+E(x.mtu||'1320')+'">')+
      row('Persistent keepalive','<input id="avkeep" value="'+E(x.keepalive||'15')+'">')+
      row('IP masquerading','<input id="avmasq" type="checkbox" '+(x.masquerade!==false?'checked':'')+'>')+
      row('Remote LAN access','<input id="avlocal" type="checkbox" '+(x.local_access?'checked':'')+'>')+
      row('Replace previously generated AirVPN profiles','<input id="avclean" type="checkbox" '+(x.cleanup_managed!==false?'checked':'')+'>')+
    '</div>'+
    '<div class="avactions"><button data-a="save">Save</button><button data-a="preview">Preview Servers</button><button data-a="sync">Sync Profiles</button><button class="secondary" data-a="cache">Clear Cache</button></div>'+
    '<div id="avmsg" class="avmsg">'+E(cache.output||'No cached selections.')+'</div><div id="avtable"></div>'+
  '</div>'+
  '<div class="avtabpane" data-avpane="diagnostics" role="tabpanel">'+
    '<div class="avdiaggen"><label for="avdiagserver"><strong>Generator/Profile Diagnostic</strong></label><div class="muted">Forces fresh AirVPN profile generation without importing it or changing VPN Dashboard state. It benchmarks successful generator request shapes and saves the fastest header-auth method as the Add Server fast path (or a proven compatibility method if header auth does not work). Leave the server blank to auto-select an unmanaged server. API/private keys are redacted so the output is safe to paste for troubleshooting.</div><div class="avdiaggenrow"><input id="avdiagserver" placeholder="Optional exact AirVPN server name"><button data-a="gen-diag">Run Generator Diagnostic</button></div><div id="avdiagprogress" class="avdiagprogress" hidden aria-live="polite"><div class="avdiagprogresshead"><span id="avdiagstage">Preparing…</span><strong id="avdiagpct">0%</strong></div><div class="avdiagprogressrail" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><div class="avdiagprogressbar"></div></div><div id="avdiagelapsed" class="muted">Elapsed: 0s</div></div></div>'+
    '<div class="avactions"><button data-a="validate">Validate Connection</button><button class="secondary" data-a="selftest">Run Self-Test</button><button class="secondary" data-a="diag">Export Diagnostics</button><button class="secondary" data-a="rollback">Rollback Last Change</button></div>'+
    '<pre id="avdiag" class="avdiag">Diagnostics have not been run yet.</pre>'+
  '</div>';

  A.favorites=csvList(x.favorites||'');
  A.serverExclusions=csvList(x.server_exclusions||'');
  var savedSelectors=csvList(x.selectors||'');
  A.selectedServer=(savedSelectors.length===1?savedSelectors[0]:'');
  A.columnOrder=normalizeColumnOrder(x.column_order||AV_DEFAULT_COLUMN_ORDER.join(','));
  A.hiddenColumns=normalizeHiddenColumns(x.hidden_columns||'');
  p.addEventListener('click',act);
  p.addEventListener('click',function(e){
    var b=e.target.closest('[data-avtab]');if(!b)return;
    selectAirTab(b.dataset.avtab);
  });
  if(A.documentPointerHandler){try{document.removeEventListener('pointerdown',A.documentPointerHandler,true)}catch(_){}}
  A.documentPointerHandler=function(e){
    if(!e.target.closest('.avselectwrap'))closeSelectMenus();
    var live=document.getElementById('airvpn-provider-view');
    var menu=live&&live.querySelector('details.avcolumns');
    if(!menu||!menu.open)return;
    if(menu.contains(e.target))return;
    menu.open=false;
  };
  document.addEventListener('pointerdown',A.documentPointerHandler,true);

  function selectAirTab(name){
    p.querySelectorAll('[data-avtab]').forEach(function(b){
      var on=b.dataset.avtab===name;
      b.classList.toggle('active',on);
      b.setAttribute('aria-selected',on?'true':'false');
    });
    p.querySelectorAll('[data-avpane]').forEach(function(pane){
      pane.hidden=pane.dataset.avpane!==name;
    });
    A.activeAirTab=name;
    if(name==='browser')refreshVpnPower();
  }

  selectAirTab(firstTab);
  setColumnOptionCheckboxes();

  A.apiKeyDirty=false;
  var apiKeyInput=document.getElementById('ava');
  if(apiKeyInput){
    apiKeyInput.value='';
    apiKeyInput.addEventListener('input',function(){
      // Only a focused manual edit may replace the stored API key.
      if(document.activeElement===apiKeyInput)A.apiKeyDirty=true;
    });
  }
  var sortSel=document.getElementById('avsort'),dirSel=document.getElementById('avdir');
  if(sortSel)sortSel.addEventListener('change',markSortDirty);
  if(dirSel)dirSel.addEventListener('change',markSortDirty);
  var countrySel=document.getElementById('avcatalogcountry');
  if(countrySel)countrySel.addEventListener('change',function(){filterCountry(countrySel.value||'ALL')});
  setSortApplyEnabled(false);

  loadCountries();
  startVpnPowerPolling();

  if(setupOk){
    loadCatalog(false).catch(function(e){
      var m=document.getElementById('avcatalogmeta');
      if(m)m.textContent='No cached server catalog yet. Click Download Servers to fetch it.';
    });
  }else{
    var m=document.getElementById('avcatalogmeta');
    if(m)m.textContent='Complete AirVPN setup in the Settings tab before downloading servers.';
  }
}
function cfg(){return{device:v('avd'),selectors:v('avs'),protocol:v('avp'),resolve:v('avr'),ip_layer:v('avl'),dns_mode:'airvpn',mtu:v('avmtu'),keepalive:v('avkeep'),local_access:c('avlocal'),masquerade:c('avmasq'),group_name:'AirVPN',prefix:'AirVPN',cleanup_managed:c('avclean'),auto_sync:false,strict_target:true,native_reload:true,discovery_mode:'best_score',health_only:c('avh'),min_score:v('avmin'),max_load:v('avmax'),include_server:v('avinc'),exclude_server:v('avexc'),country_filter:v('avcc'),use_server_discovery:c('avdisc'),sort_column:v('avsort')||((A.catalogSort&&A.catalogSort.column)||'smart_rank'),sort_direction:v('avdir')||((A.catalogSort&&A.catalogSort.direction)||'desc'),favorites:v('avfav'),server_exclusions:v('avsex'),latency_candidates:v('avlatn'),smart_rank:true,column_order:v('avcolorder')||currentColumnOrder().join(','),hidden_columns:v('avhiddencols')||hiddenColumnsCsv()}}
function saveConfigOnly(snapshot){
  snapshot=snapshot||cfg();
  A.saveChain=A.saveChain||Promise.resolve();
  A.saveChain=A.saveChain.catch(function(){}).then(function(){return rpc('set_config',snapshot)});
  return A.saveChain;
}
function save(){
  var k=v('ava').trim(),snapshot=cfg(),writeKey=!!(A.apiKeyDirty&&k);
  A.saveChain=A.saveChain||Promise.resolve();
  A.saveChain=A.saveChain.catch(function(){}).then(function(){
    var keyResult=null;
    var p=Promise.resolve();
    if(writeKey)p=rpc('set_api_key',{api_key:k}).then(function(r){keyResult=r;return rpc('api_key_status')}).then(function(st){
      if(!st||st.configured!==true||st.storage!=='uci')throw Error('API key save did not pass router UCI read-back verification.');
      var ks=document.getElementById('avkeystatus');if(ks)ks.textContent='Saved in OpenWrt UCI'+(st.validated?' — validated by AirVPN':' — validation pending');
      return st;
    });
    return p.then(function(){return rpc('set_config',snapshot)}).then(function(){
      var a=document.getElementById('ava');if(a&&writeKey){a.value='';a.placeholder='Saved — enter only to replace';A.apiKeyDirty=false}
      A.lastKeySaveOutput=keyResult&&keyResult.output?String(keyResult.output):'';
      return {keySaved:writeKey,keyOutput:A.lastKeySaveOutput};
    });
  });
  return A.saveChain;
}
function first(){return(v('avs')||'earth').split(/[;,\n]+/).map(function(x){return x.trim()}).filter(Boolean)[0]||'earth'}
var AV_SERVER_HEADERS=['','Server','Country','City / Location','Score','Load %','Current BW','Effective BW','Max BW','Available BW','Latency','Users','Health','Entry IP'];
var AV_SERVER_SORT=['','name','country','city','score','load','bandwidth','effective_bandwidth','max_bandwidth','available_bandwidth','latency','users','health','entry_ip'];

var AV_DEFAULT_COLUMN_ORDER=['name','country','city','score','load','bandwidth','effective_bandwidth','max_bandwidth','available_bandwidth','latency','users','health','entry_ip'];
var AV_COLUMN_META={
  name:{label:'Server',src:0},
  country:{label:'Country',src:2},
  city:{label:'City / Location',src:3},
  score:{label:'Score',src:4},
  load:{label:'Load %',src:5},
  bandwidth:{label:'Current BW',src:6},
  effective_bandwidth:{label:'Effective BW',src:7},
  max_bandwidth:{label:'Max BW',src:8},
  available_bandwidth:{label:'Available BW',src:-1},
  latency:{label:'Latency',src:-2},
  users:{label:'Users',src:9},
  health:{label:'Health',src:10},
  entry_ip:{label:'Entry IP',src:14}
};
var AV_ACTION_WIDTH=132;
var AV_COLUMN_WIDTH={
  name:130,
  country:105,
  city:135,
  score:72,
  load:72,
  bandwidth:105,
  effective_bandwidth:118,
  max_bandwidth:100,
  available_bandwidth:115,
  latency:82,
  users:68,
  health:82,
  entry_ip:128
};
function columnWidthFor(key){
  return AV_COLUMN_WIDTH[key]||120;
}
function normalizeColumnOrder(value){
  var seen={},out=[];
  String(value||'').split(',').map(function(x){return x.trim()}).forEach(function(k){
    if(AV_COLUMN_META[k]&&!seen[k]){seen[k]=1;out.push(k)}
  });
  AV_DEFAULT_COLUMN_ORDER.forEach(function(k){if(!seen[k]){seen[k]=1;out.push(k)}});
  return out;
}
A.columnOrder=A.columnOrder||AV_DEFAULT_COLUMN_ORDER.slice();
function currentColumnOrder(){
  var order=normalizeColumnOrder(A.columnOrder.join(','));
  var i=order.indexOf('name');
  if(i>0){order.splice(i,1);order.unshift('name')}
  return order;
}
function normalizeHiddenColumns(value){
  var hidden={};
  String(value||'').split(',').map(function(x){return x.trim()}).forEach(function(k){
    if(k!=='name'&&AV_COLUMN_META[k])hidden[k]=true;
  });
  return hidden;
}
function hiddenColumnsCsv(){
  return AV_DEFAULT_COLUMN_ORDER.filter(function(k){return !!A.hiddenColumns[k]}).join(',');
}
function visibleColumnCount(){
  return AV_DEFAULT_COLUMN_ORDER.filter(function(k){return !A.hiddenColumns[k]}).length;
}
function setColumnOptionCheckboxes(){
  document.querySelectorAll('[data-avcolumn]').forEach(function(box){
    box.checked=!A.hiddenColumns[box.dataset.avcolumn];
  });
}
function applyColumnOptions(){
  var pending={};
  document.querySelectorAll('[data-avcolumn]').forEach(function(box){
    if(box.dataset.avcolumn!=='name'&&!box.checked)pending[box.dataset.avcolumn]=true;
  });
  delete pending.name;
  var count=AV_DEFAULT_COLUMN_ORDER.filter(function(k){return !pending[k]}).length;
  if(count<1){
    var meta=document.getElementById('avcatalogmeta');
    if(meta)meta.textContent='At least one data column must remain visible.';
    setColumnOptionCheckboxes();
    return Promise.reject(new Error('At least one data column must remain visible.'));
  }
  A.hiddenColumns=pending;
  var hc=document.getElementById('avhiddencols');
  if(hc)hc.value=hiddenColumnsCsv();
  makeServerTable('avcatalogtable',A.catalogRows,true);
  return saveConfigOnly().then(function(){
    var meta=document.getElementById('avcatalogmeta');
    if(meta)meta.textContent='Column visibility saved. '+visibleColumnCount()+' data columns visible.';
  });
}

function persistColumnOrder(){
  var hidden=document.getElementById('avcolorder');
  if(hidden)hidden.value=currentColumnOrder().join(',');
  return saveConfigOnly().then(function(){
    var meta=document.getElementById('avcatalogmeta');
    if(meta)meta.textContent='Column order saved.';
  });
}
function moveColumnKey(fromKey,toKey){
  if(!fromKey||!toKey||fromKey===toKey)return false;
  if(fromKey==='name'||toKey==='name')return false;
  var order=currentColumnOrder(),from=order.indexOf(fromKey),to=order.indexOf(toKey);
  if(from<0||to<0)return false;
  order.splice(from,1);
  to=order.indexOf(toKey);
  order.splice(to,0,fromKey);
  A.columnOrder=order;
  return true;
}

function firstDefined(){
  for(var i=0;i<arguments.length;i++){
    var v=arguments[i];
    if(v!==undefined&&v!==null&&v!=='')return v;
  }
  return '';
}
function normalizeServerObject(s){
  var name=firstDefined(s.public_name,s.name);
  if(!name)return null;
  return [
    String(name),
    String(firstDefined(s.country_code,'')),
    String(firstDefined(s.country_name,s.country,'')),
    String(firstDefined(s.city_name,s.location,'')),
    String(firstDefined(s.score,0)),
    String(firstDefined(s.load,s.currentload,999)),
    String(firstDefined(s.bw,s.bandwidth,0)),
    String(firstDefined(s.effective_bandwidth,s.bw_effective,0)),
    String(firstDefined(s.bw_max,s.max_bandwidth,0)),
    String(firstDefined(s.users,0)),
    String(firstDefined(s.health,'')),
    String(firstDefined(s.available,'')),
    String(firstDefined(s.supports_ipv4,'')),
    String(firstDefined(s.supports_ipv6,'')),
    String(firstDefined(s.ip_v4_in1,s.ip_entry,''))
  ];
}
function serverKey(r){
  if(!r)return '';
  return [r[0]||'',r[1]||'',r[14]||''].join('|');
}
function findCatalogRowByKey(key){
  if(!key||!Array.isArray(A.catalogRows))return null;
  for(var i=0;i<A.catalogRows.length;i++){
    if(serverKey(A.catalogRows[i])===key)return A.catalogRows[i];
  }
  return null;
}
function parseRawStatusServers(raw){
  var obj=raw;
  if(typeof raw==='string'){try{obj=JSON.parse(raw)}catch(e){throw new Error('AirVPN returned invalid status JSON')}}
  var arr=(obj&&Array.isArray(obj.servers))?obj.servers:[];
  return arr.map(normalizeServerObject).filter(Boolean);
}
function filterCatalogRowsClient(rows,country){
  var cc=String(country||'ALL').toUpperCase();
  if(!cc||cc==='ALL')return rows.slice();
  return rows.filter(function(r){return String(r[1]||'').toUpperCase()===cc});
}
function parseRows(t){return String(t||'').trim().split(/\n/).filter(Boolean).map(function(x){return x.split('\t')})}
function bandwidthToGbps(v,isMax){
  if(v==null||v==='')return 0;
  if(typeof v==='string'){
    var s=v.trim().toLowerCase().replace(/,/g,'');
    var parsed=parseFloat(s);
    if(!isFinite(parsed))return 0;
    if(/gbit|gbps|gbit\/s/.test(s))return parsed;
    if(/mbit|mbps|mbit\/s/.test(s))return parsed/1000;
    if(/kbit|kbps|kbit\/s/.test(s))return parsed/1000000;
    if(/bytes?|b\/s/.test(s))return parsed*8/1000000000;
    v=parsed;
  }
  var n=Number(v);if(!isFinite(n)||n<0)return 0;
  if(isMax&&n>1000000)return n*8/1000000000;
  return n/1000;
}
function fmtGbps(g){
  var n=Number(g);if(!isFinite(n)||n<=0)return '0';
  if(n>=1)return n.toFixed(n>=10?0:1)+' Gbit/s';
  return (n*1000).toFixed(n>=0.1?0:1)+' Mbit/s';
}
function fmtBandwidth(v,isMax){return fmtGbps(bandwidthToGbps(v,isMax))}
function availableBandwidthGbps(row){
  if(!row)return 0;
  var avail=bandwidthToGbps(row[8],true)-bandwidthToGbps(row[6],false);
  return avail>0?avail:0;
}
function csvList(v){return String(v||'').split(/[;,\n]+/).map(function(x){return x.trim()}).filter(Boolean)}
function serverHealthFactor(r){
  var h=String(r&&r[10]||'').toLowerCase();
  if(h==='ok'||h==='healthy'||h==='good'||h==='1'||h==='true')return 1;
  if(h.indexOf('warn')>=0)return .75;
  if(h.indexOf('down')>=0||h.indexOf('offline')>=0)return .05;
  return .9;
}
function smartRankValue(r){
  var avail=availableBandwidthGbps(r),load=Math.max(0,Math.min(100,Number(r&&r[5])||0)),score=Number(r&&r[4]);
  if(!isFinite(score))score=0;
  var latency=A.latencyByServer[serverKey(r)],latencyFactor=(latency&&latency<9999)?Math.max(.25,1-(latency/500)):1;
  var favorite=A.favorites.indexOf(String(r&&r[0]||''))>=0?1.15:1;
  return avail*serverHealthFactor(r)*(1-(load/100)*.35)*latencyFactor*favorite + score/10000;
}
function isExcluded(r){return A.serverExclusions.indexOf(String(r&&r[0]||''))>=0}
function bestServerRow(){return (A.catalogRows||[]).filter(function(r){return !isExcluded(r)}).slice().sort(function(a,b){return smartRankValue(b)-smartRankValue(a)})[0]||null}
function displayCell(v,i){
  if(i===6||i===7)return fmtBandwidth(v,false);
  if(i===8)return fmtBandwidth(v,true);
  return E(v||'');
}
var AV_SERVER_VISIBLE_INDEX=[0,2,3,4,5,6,7,8,-1,-2,9,10,14];
var AV_KNOWN_COUNTRIES=[['AT','Austria'],['BE','Belgium'],['BG','Bulgaria'],['BR','Brazil'],['CA','Canada'],['CH','Switzerland'],['CZ','Czech Republic'],['DE','Germany'],['EE','Estonia'],['ES','Spain'],['GB','United Kingdom'],['IE','Ireland'],['JP','Japan'],['LV','Latvia'],['NL','Netherlands'],['NO','Norway'],['NZ','New Zealand'],['RO','Romania'],['RS','Serbia'],['SE','Sweden'],['SG','Singapore'],['TW','Taiwan'],['US','United States']];
A.catalogRows=A.catalogRows||[];
A.catalogAllRows=A.catalogAllRows||[];
A.latencyByServer=A.latencyByServer||{};
A.favorites=A.favorites||[];
A.serverExclusions=A.serverExclusions||[];
A.selectedServer=A.selectedServer||'';
A.vpnPowerPollTimer=A.vpnPowerPollTimer||null;
A.documentPointerHandler=A.documentPointerHandler||null;
A.tableResizeObserver=A.tableResizeObserver||null;
A.viewToken=A.viewToken||0;
A.latencyRunToken=A.latencyRunToken||0;
A.catalogLoadToken=A.catalogLoadToken||0;
A.vpnPowerRefreshBusy=false;
A.hiddenColumns=A.hiddenColumns||{};
A.catalogCountry=A.catalogCountry||'ALL';
A.catalogSort=A.catalogSort||{column:'smart_rank',direction:'desc'};
A.fitColumns=(A.fitColumns!==false);

function makeServerTable(target,t,sortable){
  var rows=Array.isArray(t)?t:parseRows(t),z=document.getElementById(target);if(!z)return;
  if(!rows.length){z.innerHTML='<div class="avmsg">No servers returned for this selection.</div>';return}

  var order=currentColumnOrder();
  var shell=document.createElement('div');shell.className='avtableshell'+(A.fitColumns?'':' avshowall');
  var topScroll=document.createElement('div');topScroll.className='avtopscroll';
  var topInner=document.createElement('div');topInner.className='avtopscroll-inner';
  topScroll.appendChild(topInner);
  var wrap=document.createElement('div');wrap.className='tablewrap';
  var table=document.createElement('table');
  var colgroup=document.createElement('colgroup');

  var actionCol=document.createElement('col');
  actionCol.style.width=AV_ACTION_WIDTH+'px';
  actionCol.style.minWidth=AV_ACTION_WIDTH+'px';
  colgroup.appendChild(actionCol);

  order.forEach(function(key){
    if(A.hiddenColumns[key])return;
    var col=document.createElement('col'),w=columnWidthFor(key);
    col.dataset.columnKey=key;
    col.style.width=w+'px';
    col.style.minWidth=w+'px';
    colgroup.appendChild(col);
  });
  table.appendChild(colgroup);

  var thead=document.createElement('thead'),trh=document.createElement('tr');

  var actionTh=document.createElement('th');
  actionTh.className='avactioncol';
  actionTh.style.width=AV_ACTION_WIDTH+'px';actionTh.style.minWidth=AV_ACTION_WIDTH+'px';actionTh.style.maxWidth=AV_ACTION_WIDTH+'px';
  actionTh.textContent='Actions';
  trh.appendChild(actionTh);

  order.forEach(function(key){
    if(A.hiddenColumns[key])return;
    var meta=AV_COLUMN_META[key];if(!meta)return;
    var th=document.createElement('th');
    var active=sortable&&A.catalogSort&&A.catalogSort.column===key;
    th.textContent=meta.label+(active?(A.catalogSort.direction==='asc'?' ▲':' ▼'):(sortable?' ↕':''));
    th.dataset.columnKey=key;
    if(key==='name')th.classList.add('avservernamecol');
    th.style.width=columnWidthFor(key)+'px';
    th.style.minWidth=columnWidthFor(key)+'px';
    th.style.maxWidth=columnWidthFor(key)+'px';
    th.draggable=key!=='name';
    th.title=(key==='name'?'Pinned column':('Drag to move '+meta.label))+(sortable?' · Click to sort':'');
    th.classList.add('avdraggable');
    if(sortable){
      th.dataset.sort=key;
      if(active)th.setAttribute('aria-sort',A.catalogSort.direction==='asc'?'ascending':'descending');
    }
    trh.appendChild(th);
  });
  thead.appendChild(trh);table.appendChild(thead);

  var tbody=document.createElement('tbody');
  var frag=document.createDocumentFragment();

  rows.forEach(function(r,rowIndex){
    var tr=document.createElement('tr');
    var sk=serverKey(r);
    tr.dataset.serverKey=sk;
    if(A.selectedServer===String(r[0]||''))tr.classList.add('avselectedserver');

    var actionTd=document.createElement('td');actionTd.className='avactioncol';
    actionTd.style.width=AV_ACTION_WIDTH+'px';actionTd.style.minWidth=AV_ACTION_WIDTH+'px';actionTd.style.maxWidth=AV_ACTION_WIDTH+'px';
    var actionWrap=document.createElement('div');actionWrap.className='rowactions';

    var infoButton=document.createElement('button');
    infoButton.type='button';
    infoButton.className='rowbtn info';
    infoButton.textContent='Info';
    infoButton.dataset.serverAction='info';
    infoButton.dataset.serverKey=sk;
    infoButton.title='View server details';
    actionWrap.appendChild(infoButton);
    actionWrap.appendChild(makeSelectMenu(sk,A.selectedServer===String(r[0]||'')));
    actionTd.appendChild(actionWrap);tr.appendChild(actionTd);

    order.forEach(function(key){
      if(A.hiddenColumns[key])return;
      var meta=AV_COLUMN_META[key];if(!meta)return;
      var td=document.createElement('td'),srcIndex=meta.src,w=columnWidthFor(key);
      td.dataset.columnKey=key;
      if(key==='name')td.classList.add('avservernamecol');
      td.style.width=w+'px';
      td.style.minWidth=w+'px';
      td.style.maxWidth=w+'px';
      if(srcIndex===-1)td.textContent=fmtGbps(availableBandwidthGbps(r));
      else if(srcIndex===-2){
        var lat=A.latencyByServer[serverKey(r)];
        td.textContent=(lat&&lat<9999)?(Number(lat).toFixed(1)+' ms'):'—';
      }else{
        var val=r[srcIndex]==null?'':r[srcIndex];
        if(srcIndex===6||srcIndex===7)td.textContent=fmtBandwidth(val,false);
        else if(srcIndex===8)td.textContent=fmtBandwidth(val,true);
        else td.textContent=String(val);
      }
      tr.appendChild(td);
    });

    frag.appendChild(tr);
  });

  tbody.appendChild(frag);table.appendChild(tbody);wrap.appendChild(table);
  var viewHint=document.createElement('div');viewHint.className='avtableviewhint';
  viewHint.innerHTML='<span>'+(A.fitColumns?'Fit view: essential columns stay visible; lower-priority columns collapse as the panel narrows.':'All selected columns are shown; horizontal table scrolling may be required.')+'</span>';
  shell.appendChild(viewHint);shell.appendChild(topScroll);shell.appendChild(wrap);
  z.replaceChildren(shell);

  function syncTopScrollbar(){
    var sw=Math.max(table.scrollWidth,wrap.scrollWidth);
    topInner.style.width=sw+'px';
    topScroll.style.display=sw>wrap.clientWidth?'block':'none';
  }
  var syncing=false;
  topScroll.addEventListener('scroll',function(){
    if(syncing)return;syncing=true;wrap.scrollLeft=topScroll.scrollLeft;syncing=false;
  });
  wrap.addEventListener('scroll',function(){
    if(syncing)return;syncing=true;topScroll.scrollLeft=wrap.scrollLeft;syncing=false;
  });

  bindColumnDragging(table);
  requestAnimationFrame(syncTopScrollbar);
  setTimeout(syncTopScrollbar,50);
  if(A.tableResizeObserver){try{A.tableResizeObserver.disconnect()}catch(_){}A.tableResizeObserver=null;}
  if(window.ResizeObserver){
    var tableObserver=new ResizeObserver(function(){
      if(!table.isConnected){
        try{tableObserver.disconnect()}catch(_){}
        if(A.tableResizeObserver===tableObserver)A.tableResizeObserver=null;
        return;
      }
      table.style.tableLayout='fixed';syncTopScrollbar();
    });
    A.tableResizeObserver=tableObserver;
    tableObserver.observe(wrap);tableObserver.observe(table);
  }
}
function bindColumnDragging(table){
  var dragged='';
  table.querySelectorAll('th[data-column-key]').forEach(function(th){
    th.addEventListener('dragstart',function(e){
      dragged=th.dataset.columnKey||'';
      th.classList.add('avdragging');
      try{e.dataTransfer.effectAllowed='move';e.dataTransfer.setData('text/plain',dragged)}catch(_){}
    });
    th.addEventListener('dragend',function(){
      th.classList.remove('avdragging');
      table.querySelectorAll('.avdragover').forEach(function(x){x.classList.remove('avdragover')});
      dragged='';
    });
    th.addEventListener('dragover',function(e){
      e.preventDefault();
      if(!dragged||dragged===th.dataset.columnKey)return;
      th.classList.add('avdragover');
      try{e.dataTransfer.dropEffect='move'}catch(_){}
    });
    th.addEventListener('dragleave',function(){th.classList.remove('avdragover')});
    th.addEventListener('drop',function(e){
      e.preventDefault();th.classList.remove('avdragover');
      var from=dragged;
      try{from=e.dataTransfer.getData('text/plain')||from}catch(_){}
      var to=th.dataset.columnKey||'';
      if(moveColumnKey(from,to)){
        makeServerTable('avcatalogtable',A.catalogRows,true);
        persistColumnOrder().catch(function(err){
          var meta=document.getElementById('avcatalogmeta');
          if(meta)meta.textContent='Column moved, but saving the order failed: '+err.message;
        });
      }
    });
  });
}function table(t){makeServerTable('avtable',t,false)}
function catalogColumnIndex(key){
  var map={name:0,country_code:1,country:2,city:3,score:4,load:5,bandwidth:6,effective_bandwidth:7,max_bandwidth:8,available_bandwidth:8,latency:0,smart_rank:0,users:9,health:10,available:11,supports_ipv4:12,supports_ipv6:13,entry_ip:14};
  return Object.prototype.hasOwnProperty.call(map,key)?map[key]:0;
}
function catalogNumeric(key){
  return ['score','load','bandwidth','effective_bandwidth','max_bandwidth','available_bandwidth','latency','smart_rank','users'].indexOf(key)>=0;
}
function sortCatalogInMemory(key,direction){
  if(!Array.isArray(A.catalogRows)||!A.catalogRows.length)return;
  var idx=catalogColumnIndex(key),numeric=catalogNumeric(key),dir=direction==='asc'?1:-1;
  A.catalogRows.sort(function(a,b){
    var av=a[idx]==null?'':a[idx],bv=b[idx]==null?'':b[idx];
    if(numeric){
      var an,bn;
      if(key==='available_bandwidth'){
        an=availableBandwidthGbps(a);bn=availableBandwidthGbps(b);
      }else if(key==='smart_rank'){
        an=smartRankValue(a);bn=smartRankValue(b);
      }else if(key==='latency'){
        an=A.latencyByServer[serverKey(a)]||9999;bn=A.latencyByServer[serverKey(b)]||9999;
      }else if(key==='max_bandwidth'){
        an=bandwidthToGbps(av,true);bn=bandwidthToGbps(bv,true);
      }else if(key==='bandwidth'||key==='effective_bandwidth'){
        an=bandwidthToGbps(av,false);bn=bandwidthToGbps(bv,false);
      }else{
        an=Number(av);bn=Number(bv);
        if(!isFinite(an))an=0;if(!isFinite(bn))bn=0;
      }
      if(an<bn)return -1*dir;if(an>bn)return 1*dir;
    }else{
      var as=String(av).toLowerCase(),bs=String(bv).toLowerCase();
      var c=as.localeCompare(bs,undefined,{numeric:true,sensitivity:'base'});
      if(c)return c*dir;
    }
    return String(a[0]||'').localeCompare(String(b[0]||''),undefined,{numeric:true,sensitivity:'base'});
  });
  A.catalogSort={column:key,direction:direction};
  var sortSelect=document.getElementById('avsort'),dirSelect=document.getElementById('avdir');
  if(sortSelect)sortSelect.value=key;
  if(dirSelect)dirSelect.value=direction;
  makeServerTable('avcatalogtable',A.catalogRows,true);
  var meta=document.getElementById('avcatalogmeta');
  if(meta)meta.textContent=A.catalogRows.length+' server'+(A.catalogRows.length===1?'':'s')+' — '+(A.catalogCountry==='ALL'?'All countries':A.catalogCountry)+' — sorted locally by '+key+' '+direction+'.';
}
function toggleCatalogSort(key){
  var direction=(A.catalogSort&&A.catalogSort.column===key&&A.catalogSort.direction==='asc')?'desc':'asc';
  sortCatalogInMemory(key,direction);
}
function loadCountries(){
  var s=document.getElementById('avcatalogcountry');if(!s)return;
  var previous=s.value||'ALL';
  function renderCountries(rows,source){
    if(!rows||!rows.length)return;
    var seen={};
    var clean=rows.filter(function(x){
      var cc=String(x[0]||'').toUpperCase(),name=String(x[1]||'').trim();
      if(!cc||!name||seen[cc])return false;
      seen[cc]=1;x[0]=cc;x[1]=name;return true;
    }).sort(function(a,b){return String(a[1]).localeCompare(String(b[1]),undefined,{sensitivity:'base'})});
    s.innerHTML='<option value="ALL">All</option>'+clean.map(function(x){return'<option value="'+E(x[0])+'">'+E(x[1]+' ('+x[0]+')')+'</option>'}).join('');
    if(previous==='ALL'||seen[previous])s.value=previous;else s.value='ALL';
    A.countryListSource=source;
    A.countryList=clean;
  }

  // Refresh the seeded country list from AirVPN's lightweight aggregate.
  rpc('server_countries',{}).then(function(r){
    var rows=parseRows(r.output||'');
    if(rows.length)renderCountries(rows,'live');
  }).catch(function(e){
    A.debug=A.debug||{};A.debug.countryListError=String(e&&e.message||e);
    A.countryListSource='seed';
  });
}
function setCatalogProgress(percent,text){
  var wrap=document.getElementById('avcatalogprogress');
  var bar=wrap&&wrap.querySelector('.avprogressbar');
  var meta=document.getElementById('avcatalogmeta');
  var p=Math.max(0,Math.min(100,Number(percent)||0));
  if(wrap)wrap.style.display=(p>0&&p<100)?'block':(p===100?'block':'none');
  if(bar)bar.style.width=p+'%';
  if(meta&&text)meta.textContent=text;
  if(p===100)setTimeout(function(){if(wrap)wrap.style.display='none';if(bar)bar.style.width='0%'},700);
}
function animateCatalogProgress(){
  if(A.catalogProgressTimer){clearInterval(A.catalogProgressTimer);A.catalogProgressTimer=null}
  setCatalogProgress(10,'Requesting raw AirVPN status JSON…');
}
function stopCatalogProgress(success,count,country){
  if(A.catalogProgressTimer){clearInterval(A.catalogProgressTimer);A.catalogProgressTimer=null}
  if(success)setCatalogProgress(100,(count||0)+' server'+((count||0)===1?'':'s')+' loaded — '+(country==='ALL'?'All countries':country)+'.');
  else setCatalogProgress(0);
}
function nextFrame(){return new Promise(function(resolve){requestAnimationFrame(function(){resolve()})})}
function downloadText(name,text){
  var blob=new Blob([text],{type:'text/plain;charset=utf-8'}),u=URL.createObjectURL(blob),a=document.createElement('a');
  a.href=u;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(function(){URL.revokeObjectURL(u)},1000);
}
function latencyRowsTop(){
  return (A.catalogRows||[]).filter(function(r){return r[14]&&!isExcluded(r)}).slice().sort(function(a,b){return availableBandwidthGbps(b)-availableBandwidthGbps(a)}).slice(0,Math.max(1,Math.min(20,Number(v('avlatn'))||12)));
}
function latencyRowsAll(){
  // Use the rows currently visible after filtering and exclusions.
  return (A.catalogRows||[]).filter(function(r){return !isExcluded(r)}).slice();
}
function setLatencyVerbosity(showDetails){
  var details=document.getElementById('avlatencydetails');
  var basic=document.querySelector('[data-a="latency-basic"]');
  var verbose=document.querySelector('[data-a="latency-details"]');
  if(details)details.hidden=!showDetails;
  if(basic)basic.classList.toggle('active',!showDetails);
  if(verbose){verbose.classList.toggle('active',showDetails);verbose.textContent=showDetails?'Show Details':'Show Details';}
}
function setLatencyButtonsBusy(busy){
  document.querySelectorAll('[data-a="latency"],[data-a="latency-all"]').forEach(function(b){b.disabled=!!busy});
}
function setBrowserMutationBusy(busy){
  document.querySelectorAll('[data-a="catalog"],[data-a="best"],[data-server-action="connect"],[data-server-action="add-profile"]').forEach(function(b){b.disabled=!!busy});
  var c=document.getElementById('avcatalogcountry');if(c)c.disabled=!!busy;
}
function openLatencyProgress(title,total){
  var d=document.getElementById('avlatencydialog');if(!d)return;
  d.hidden=false;
  var t=document.getElementById('avlatencytitle');if(t)t.textContent=title;
  var s=document.getElementById('avlatencystatus');if(s)s.textContent='Starting latency test…';
  var c=document.getElementById('avlatencycurrent');if(c)c.textContent='Preparing server list…';
  var n=document.getElementById('avlatencycount');if(n)n.textContent='0 / '+total;
  var p=document.getElementById('avlatencypercent');if(p)p.textContent='0%';
  var bar=d.querySelector('.avlatencyprogressbar');if(bar)bar.style.width='0%';
  var wrap=d.querySelector('.avlatencyprogress');if(wrap)wrap.setAttribute('aria-valuenow','0');
  var log=document.getElementById('avlatencylog');if(log)log.innerHTML='';
  setLatencyVerbosity(false);
}
function updateLatencyProgress(done,total,current,statusText){
  var pct=total?Math.round((done/total)*100):100;
  var c=document.getElementById('avlatencycurrent');if(c)c.textContent=current||'';
  var n=document.getElementById('avlatencycount');if(n)n.textContent=done+' / '+total;
  var p=document.getElementById('avlatencypercent');if(p)p.textContent=pct+'%';
  var s=document.getElementById('avlatencystatus');if(s&&statusText)s.textContent=statusText;
  var d=document.getElementById('avlatencydialog');
  var bar=d&&d.querySelector('.avlatencyprogressbar');if(bar)bar.style.width=pct+'%';
  var wrap=d&&d.querySelector('.avlatencyprogress');if(wrap)wrap.setAttribute('aria-valuenow',String(pct));
}
function latencyCountry(r){
  var name=String((r&&r[2])||'').trim(),code=String((r&&r[1])||'').trim();
  return name||(code||'Unknown country');
}
function addLatencyDetail(name,country,host,result,kind){
  var log=document.getElementById('avlatencylog');if(!log)return;
  var row=document.createElement('div');row.className='avlatencylogrow '+(kind||'');
  row.innerHTML='<span>'+E(name||'Unknown')+'</span><span>'+E(country||'Unknown country')+'</span><span>'+E(host||'—')+'</span><span>'+E(result||'—')+'</span>';
  log.appendChild(row);
  // Keep the newest latency result visible.
  if(!document.getElementById('avlatencydetails').hidden)log.scrollTop=log.scrollHeight;
}
var AV_LATENCY_PARALLELISM=12;
function runLatencyTest(rows,label){
  if(A.latencyTesting)return;
  var runToken=(A.latencyRunToken||0)+1;A.latencyRunToken=runToken;
  var viewToken=A.viewToken;
  function stale(){return runToken!==A.latencyRunToken||viewToken!==A.viewToken||!A.mode}
  rows=(rows||[]).slice();
  if(!rows.length){
    var meta=document.getElementById('avcatalogmeta');if(meta)meta.textContent='No servers are currently available for latency testing.';
    return;
  }
  A.latencyTesting=true;
  setLatencyButtonsBusy(true);
  setBrowserMutationBusy(true);
  openLatencyProgress(label,rows.length);
  var meta=document.getElementById('avcatalogmeta');
  if(meta)meta.textContent=label+' — '+rows.length+' server'+(rows.length===1?'':'s')+' using up to '+AV_LATENCY_PARALLELISM+' parallel router workers.';
  var done=0,measured=0,unreachable=0,skipped=0,finished=false;
  var jobs=[];
  rows.forEach(function(r){
    var name=String(r[0]||'Unknown'),country=latencyCountry(r),host=String(r[14]||'').trim();
    if(!host){
      skipped++;done++;addLatencyDetail(name,country,'—','Skipped — no entry IP','skipped');
      return;
    }
    jobs.push({row:r,name:name,country:country,host:host});
  });
  function finish(){
    if(stale()||finished)return;finished=true;
    makeServerTable('avcatalogtable',A.catalogRows,true);
    var summary='Complete — '+measured+' measured';
    if(unreachable)summary+=', '+unreachable+' unreachable';
    if(skipped)summary+=', '+skipped+' skipped';
    summary+='.';
    updateLatencyProgress(rows.length,rows.length,'Latency test complete',summary);
    if(meta)meta.textContent='Latency test complete. Smart Rank now includes measured latency for this server list.';
    A.latencyTesting=false;
    setLatencyButtonsBusy(false);
    setBrowserMutationBusy(false);
  }
  function runBatch(start){
    if(stale())return;
    if(start>=jobs.length){finish();return;}
    var batch=jobs.slice(start,start+AV_LATENCY_PARALLELISM);
    var countries=[];
    batch.forEach(function(j){if(countries.indexOf(j.country)<0)countries.push(j.country)});
    var countryText=countries.slice(0,3).join(', ')+(countries.length>3?' +'+(countries.length-3)+' more':'');
    updateLatencyProgress(done,rows.length,'Testing '+batch.length+' servers concurrently — '+countryText+'…',
      'Running '+batch.length+' parallel latency workers on the router…');
    var targets=batch.map(function(j){return j.name+'|'+j.host}).join(',');
    rpc('latency_test',{targets:targets}).then(function(res){
      if(stale())return;
      var resultRows=parseRows(res.output||'');
      var byName={};
      resultRows.forEach(function(x){byName[String(x[0]||'')]=x});
      batch.forEach(function(j){
        var x=byName[j.name]||null,avg=x?Number(x[2]):9999;
        if(!isFinite(avg)||avg<=0)avg=9999;
        A.latencyByServer[serverKey(j.row)]=avg;
        done++;
        if(avg>=9999){
          unreachable++;
          addLatencyDetail(j.name,j.country,j.host,'Unreachable / timed out','failed');
        }else{
          measured++;
          addLatencyDetail(j.name,j.country,j.host,avg.toFixed(1)+' ms','ok');
        }
      });
      var last=batch[batch.length-1];
      updateLatencyProgress(done,rows.length,last.name+' — '+last.country,
        'Completed '+done+' of '+rows.length+'; '+Math.min(AV_LATENCY_PARALLELISM,jobs.length-start-batch.length)+' workers queued for the next batch.');
    }).catch(function(err){
      if(stale())return;
      batch.forEach(function(j){
        done++;unreachable++;A.latencyByServer[serverKey(j.row)]=9999;
        addLatencyDetail(j.name,j.country,j.host,'Error — '+String(err&&err.message||err),'failed');
      });
      updateLatencyProgress(done,rows.length,'Latency batch error','A parallel latency batch failed; continuing with the remaining servers.');
    }).then(function(){if(stale())return null;return nextFrame()}).then(function(){if(!stale())runBatch(start+batch.length)});
  }
  if(done)updateLatencyProgress(done,rows.length,'Preparing parallel latency workers',skipped+' server'+(skipped===1?'':'s')+' skipped — no usable entry IP.');
  if(!jobs.length){finish();return;}
  runBatch(0);
}
function testTopLatency(){runLatencyTest(latencyRowsTop(),'Test Top Latency')}
function testAllLatency(){runLatencyTest(latencyRowsAll(),'Test All Latency')}
function loadCatalog(forceRefresh){
  var country=v('avcatalogcountry')||'ALL',meta=document.getElementById('avcatalogmeta');
  if(A.catalogLoading){if(meta)meta.textContent='AirVPN server data is already loading…';return A.catalogLoading;}
  var loadToken=(A.catalogLoadToken||0)+1;A.catalogLoadToken=loadToken;
  var viewToken=A.viewToken;
  function stale(){return loadToken!==A.catalogLoadToken||viewToken!==A.viewToken||!A.mode}
  if(A.catalogProgressTimer){clearInterval(A.catalogProgressTimer);A.catalogProgressTimer=null}

  var method=forceRefresh?'raw_status_refresh':'raw_status';
  setCatalogProgress(forceRefresh?8:18,forceRefresh?'Downloading fresh AirVPN server data…':'Loading cached AirVPN server data…');

  var task=rpc(method,{}).then(function(raw){
    if(stale())return null;
    setCatalogProgress(42,(forceRefresh?'Fresh':'Cached')+' AirVPN status received. Parsing servers in your browser…');
    return nextFrame().then(function(){
      if(stale())return null;
      var rows=parseRawStatusServers(raw);
      A.catalogAllRows=rows.slice();
      setCatalogProgress(58,'Parsed '+rows.length+' AirVPN server records locally…');
      return nextFrame().then(function(){
        if(stale())return null;
        setCatalogProgress(70,'Applying '+(country==='ALL'?'no country filter':'country filter '+country)+' in your browser…');
        rows=filterCatalogRowsClient(A.catalogAllRows||rows,country).filter(function(r){return !isExcluded(r)});
        A.catalogRows=rows;
        A.catalogCountry=country;
        A.catalogSort={column:v('avsort')||'smart_rank',direction:v('avdir')||'desc'};
        setCatalogProgress(80,'Normalizing bandwidth values and sorting '+rows.length+' rows locally…');
        sortCatalogInMemory(A.catalogSort.column,A.catalogSort.direction);
        return nextFrame();
      }).then(function(){
        if(stale())return null;
        setCatalogProgress(92,'Building '+rows.length+' server rows in your browser…');
        makeServerTable('avcatalogtable',A.catalogRows,true);
        return nextFrame();
      }).then(function(){
        if(stale())return null;
        setCatalogProgress(99,'Finalizing row actions and horizontal scrolling…');
        return nextFrame();
      }).then(function(){
        if(stale())return null;
        stopCatalogProgress(true,A.catalogRows.length,country);
        return rpc('raw_status_meta',{}).then(function(metaInfo){
          if(stale())return null;
          A.rawStatusMeta=metaInfo||{};
          var m=document.getElementById('avcatalogmeta');
          if(m && metaInfo && metaInfo.age_seconds!==undefined){
            var age=Math.max(0,Number(metaInfo.age_seconds)||0),mins=Math.floor(age/60),hrs=Math.floor(mins/60),rem=mins%60;
            var ageText=hrs>0?(hrs+'h '+rem+'m'):(mins+'m');
            var refreshNote=(String(metaInfo.last_refresh_ok)==='0')?' — last refresh FAILED: '+(metaInfo.last_refresh_message||'unknown error'):'';
            var sched=(metaInfo.schedule_minute!=='')?' — 5h refresh @ randomized minute '+String(metaInfo.schedule_minute).padStart(2,'0'):'';
            if(metaInfo.next_refresh_due){var left=Math.max(0,Number(metaInfo.next_refresh_due)*1000-Date.now()),lh=Math.floor(left/3600000),lm=Math.floor((left%3600000)/60000);sched+=' — next due ~'+lh+'h '+lm+'m';}
            m.textContent=A.catalogRows.length+' server'+(A.catalogRows.length===1?'':'s')+' — '+(country==='ALL'?'All countries':country)+' — cache age '+ageText+sched+refreshNote+'.';
          }
        }).catch(function(){});
      });
    });
  }).catch(function(err){
    if(stale())return null;
    stopCatalogProgress(false,0,country);
    if(meta)meta.textContent='Server download failed: '+(err&&err.message||err);
    throw err;
  });
  A.catalogLoading=task.finally(function(){if(loadToken===A.catalogLoadToken)A.catalogLoading=null;});
  return A.catalogLoading;
}
function closeServerModal(){
  var m=document.getElementById('av-server-modal');
  if(m)m.remove();
}
function closeProfileResultPrompt(){
  var m=document.getElementById('av-profile-result-modal');
  if(m)m.remove();
}
function showProfileResultPrompt(ok,title,detail){
  closeProfileResultPrompt();
  var m=document.createElement('div');
  m.id='av-profile-result-modal';m.className='avmodal';
  var resultLabel=ok?'SUCCESS':(/^BUSY\b/i.test(String(title||''))?'BUSY':'FAILED');
  m.innerHTML='<div class="avmodalcard avresultcard '+(ok?'pass':'fail')+'" role="alertdialog" aria-modal="true" aria-label="'+E(title)+'">'+
    '<div class="avmodalhead"><div><strong class="avresulttitle">'+E(resultLabel)+' — '+E(title.replace(/^BUSY\s*[—-]?\s*/i,''))+'</strong></div></div>'+
    '<div class="avresultbody">'+E(detail||'').replace(/\n/g,'<br>')+'</div>'+
    '<div class="avmodalactions"><button type="button" data-profile-result-close>OK</button></div></div>';
  document.body.appendChild(m);
  m.addEventListener('click',function(ev){if(ev.target===m||ev.target.closest('[data-profile-result-close]'))closeProfileResultPrompt()});
}
function closeSelectMenus(except){
  document.querySelectorAll('.avselectmenu.open').forEach(function(m){
    if(except&&m===except)return;
    m.classList.remove('open');
    var row=m.closest('tr');if(row)row.classList.remove('avmenurow');
    var cell=m.closest('td');if(cell)cell.classList.remove('avmenucell');
  });
}
function makeSelectMenu(sk,selected){
  var wrap=document.createElement('div');
  wrap.className='avselectwrap';

  var b=document.createElement('button');
  b.type='button';
  // Selection state is shown by the row highlight; this remains an action menu.
  b.className='rowbtn use avselecttrigger';
  b.textContent='Select ▾';
  b.dataset.selectMenu=sk;
  b.title=selected?'Current AirVPN selector — choose an action':'Choose what to do with this server';
  b.disabled=!!A.profileMutationBusy;

  var menu=document.createElement('div');
  menu.className='avselectmenu';
  menu.dataset.selectMenuPanel=sk;

  var add=document.createElement('button');
  add.type='button';
  add.className='avselectitem';
  add.textContent='Add server to profile';
  add.dataset.serverAction='add-profile';
  add.dataset.serverKey=sk;
  add.disabled=!!A.profileMutationBusy;

  var connect=document.createElement('button');
  connect.type='button';
  connect.className='avselectitem';
  connect.textContent='Connect Now';
  connect.dataset.serverAction='connect';
  connect.dataset.serverKey=sk;
  connect.disabled=!!A.profileMutationBusy;

  menu.appendChild(add);
  menu.appendChild(connect);
  wrap.appendChild(b);
  wrap.appendChild(menu);
  return wrap;
}
function showServerInfo(r){
  closeServerModal();
  var names=['Server','Country code','Country','City / Location','Score','Load %','Current bandwidth','Effective bandwidth','Maximum bandwidth','Users','Health','Available','IPv4 support','IPv6 support','Entry IP'];
  var rows=names.map(function(n,i){
    var v=r[i]||'';
    if(i===6||i===7)v=fmtBandwidth(v,false);
    if(i===8)v=fmtBandwidth(v,true);
    var line='<div class="avdetailrow"><div class="avdetailkey">'+E(n)+'</div><div class="avdetailval">'+E(v)+'</div></div>';
    if(i===8)line+='<div class="avdetailrow"><div class="avdetailkey">Available bandwidth</div><div class="avdetailval">'+E(fmtGbps(availableBandwidthGbps(r)))+'</div></div>';
    return line;
  }).join('');
  var m=document.createElement('div');
  m.id='av-server-modal';
  m.className='avmodal';
  m.innerHTML='<div class="avmodalcard" role="dialog" aria-modal="true" aria-label="AirVPN server details">'+
    '<div class="avmodalhead"><div><strong>'+E(r[0]||'AirVPN Server')+'</strong><div class="muted">'+E((r[3]||'')+(r[2]?' · '+r[2]:''))+'</div></div>'+
    '<button type="button" class="rowbtn" data-server-close title="Close">Close</button></div>'+
    '<div class="avdetails">'+rows+'</div></div>';
  document.body.appendChild(m);
  m.addEventListener('click',function(ev){if(ev.target===m)closeServerModal()});
}
function setProfileMutationBusy(on,label){
  A.profileMutationBusy=!!on;A.profileMutationLabel=on?(label||'AirVPN profile operation'):'';
  document.querySelectorAll('[data-server-action="add-profile"],[data-server-action="connect"],[data-select-menu]').forEach(function(el){
    if('disabled' in el)el.disabled=!!on;
    el.setAttribute('aria-disabled',on?'true':'false');
  });
}
function profileBusyMessage(){return (A.profileMutationLabel||'Another AirVPN profile operation')+' is already running. Please let it finish before starting another profile action.'}
function isBackendBusyError(err){return !!(err&&(Number(err.code)===75||/Another AirVPN operation is already running|already starting/i.test(String(err.message||''))))}
function setProfileMutationProgress(st){
  var box=document.getElementById('avprofileprogress');if(!box)return;
  box.hidden=false;
  var stage=document.getElementById('avprofilestage');if(stage)stage.textContent=(st.stage||'Working…')+(st.stageCode?' ['+st.stageCode+']':'');
  var pct=document.getElementById('avprofilepct');if(pct)pct.textContent=Math.round(st.percent||0)+'%';
  var elapsed=document.getElementById('avprofileelapsed');if(elapsed)elapsed.textContent='Elapsed: '+Math.round(st.elapsed||0)+'s';
  var rail=box.querySelector('.avdiagprogressrail'),bar=box.querySelector('.avdiagprogressbar');
  if(rail)rail.setAttribute('aria-valuenow',String(Math.round(st.percent||0)));
  if(bar)bar.style.width=Math.round(st.percent||0)+'%';
}
function addProfileFailureFromStatus(st,name){
  var text=String(st&&st.output||'');
  var m=text.match(/^ADD_PROFILE_FAIL\s+stage=([^\s]+)\s+code=([^\s]+)\s+elapsed=([^\s]+)/m);
  var stage=(m&&m[1])||(st&&st.stageCode)||'unknown';
  var code=(m&&m[2])||'';
  var elapsed=(m&&m[3])||((st&&st.elapsed!=null)?String(st.elapsed)+'s':'');
  var msg='Add server failed at stage='+stage+(code?' code='+code:'')+(elapsed?' elapsed='+elapsed:'')+'.';
  if(text)msg+='\n\n'+text;
  var e=Error(msg);if(code)e.code=Number(code)||code;e.output=text;e.stage=stage;return e;
}
function runAddProfileJob(name,meta){
  setProfileMutationProgress({percent:1,stage:'Starting Add server to profile',stageCode:'queued',elapsed:0});
  return rpc('add_profile_start',{selector:name}).then(function(r){
    var job=String((r&&r.output)||'').trim().split(/\r?\n/).pop();
    if(!/^add-[0-9]+-[0-9]+$/.test(job))throw Error('Add Profile did not return a valid job ID: '+String((r&&r.output)||''));
    function poll(){
      return rpc('add_profile_status',{job:job}).then(function(sr){
        var st=parseGeneratorDiagStatus((sr&&sr.output)||'');
        setProfileMutationProgress(st);
        if(meta)meta.textContent=(st.state==='failed'?'FAILED: ':'')+(st.stage||'Adding '+name+'…')+' — '+Math.round(st.percent||0)+'% — '+Math.round(st.elapsed||0)+'s';
        if(st.state==='complete')return {output:st.output||'',status:st};
        if(st.state==='failed')throw addProfileFailureFromStatus(st,name);
        return new Promise(function(resolve){setTimeout(resolve,850)}).then(poll);
      });
    }
    return poll();
  });
}
function setServerAsSelector(r){
  if(!r||!r[0])return Promise.reject(new Error('No server selected.'));
  var name=String(r[0]);
  if(A.profileMutationBusy){
    var busy=Error(profileBusyMessage());busy.code=75;
    showProfileResultPrompt(false,'BUSY — AirVPN operation in progress',busy.message);
    return Promise.reject(busy);
  }
  setProfileMutationBusy(true,'Adding '+name+' to VPN Client Profile');
  var ta=document.getElementById('avs');
  if(ta){
    var list=csvList(ta.value||''),lower=list.map(function(x){return x.toLowerCase()});
    if(lower.indexOf(name.toLowerCase())<0)list.push(name);
    ta.value=list.join(', ');
  }

  var meta=document.getElementById('avcatalogmeta');
  if(meta)meta.textContent='Adding '+name+' to VPN Client Profile…';
  closeServerModal();

  // Persist only the selector change before starting the profile workflow.
  var selectorSave=ta?saveConfigOnly({selectors:ta.value}):Promise.resolve();
  var op=selectorSave.then(function(){
    return runAddProfileJob(name,meta);
  }).then(function(res){
    var text=String((res&&res.output)||'');
    var verified=text.split(/\r?\n/).filter(function(line){return /^DASHBOARD_VERIFIED\s/.test(line)}).pop()||'';
    var success=/^ADD_PROFILE_STATUS=SUCCESS\b/m.test(text)&&!!verified;
    if(!success)throw new Error('Backend returned without a positive native VPN Dashboard verification for '+name+'.\n'+text);
    var tid=(verified.match(/\btunnel_id=([^\s]+)/)||[])[1]||'unknown';
    var peer=(verified.match(/\bpeer=([^\s]+)/)||[])[1]||'unknown';
    if(meta)meta.textContent='SUCCESS: '+name+' was added and verified in VPN Dashboard (tunnel '+tid+', '+peer+').';
    showProfileResultPrompt(true,'Server added to profile',name+' is present in VPN Client Profile and verified in the native VPN Dashboard.\nTunnel ID: '+tid+'\nPeer: '+peer);
    return refreshVpnPower().then(function(){return name});
  }).catch(function(err){
    if(isBackendBusyError(err)){
      if(meta)meta.textContent='BUSY: '+err.message;
      showProfileResultPrompt(false,'BUSY — AirVPN operation in progress',err.message);
    }else{
      var stage=err&&err.stage?String(err.stage):'';
      var detail=(stage?'Add server to profile failed at stage: '+stage+'.':'Add server to profile failed.')+'\n\n'+err.message;
      if(meta)meta.textContent='FAILED to add server profile'+(stage?' at '+stage:'')+': '+err.message.split('\n')[0];
      showProfileResultPrompt(false,'FAILED — Add server to profile',detail);
    }
    throw err;
  });
  return op.then(function(v){setProfileMutationBusy(false);return v},function(err){setProfileMutationBusy(false);throw err});
}
function filterCountry(cc){
  var s=document.getElementById('avcatalogcountry');
  if(s&&cc){
    s.value=cc;
    var rows=filterCatalogRowsClient(A.catalogAllRows||A.catalogRows||[],cc).filter(function(r){return !isExcluded(r)});
    A.catalogRows=rows;
    A.catalogCountry=cc;
    sortCatalogInMemory((A.catalogSort&&A.catalogSort.column)||'smart_rank',(A.catalogSort&&A.catalogSort.direction)||'desc');
    closeServerModal();
    var m=document.getElementById('avcatalogmeta');
    if(m)m.textContent=A.catalogRows.length+' server'+(A.catalogRows.length===1?'':'s')+' — '+cc+' — filtered locally from cached data.';
  }
}
function parseGeneratorDiagStatus(text){
  var raw=String(text||''),mark='---OUTPUT---',i=raw.indexOf(mark),meta=i>=0?raw.slice(0,i):raw,out=i>=0?raw.slice(i+mark.length).replace(/^\s*\n/,''):'';
  var r={state:'running',percent:0,stage:'Working…',stageCode:'',elapsed:0,output:out};
  meta.split(/\r?\n/).forEach(function(line){var p=line.indexOf('=');if(p<1)return;var k=line.slice(0,p),v=line.slice(p+1);if(k==='state')r.state=v;else if(k==='percent')r.percent=Math.max(0,Math.min(100,Number(v)||0));else if(k==='stage')r.stage=v;else if(k==='stage_code')r.stageCode=v;else if(k==='elapsed')r.elapsed=Math.max(0,Number(v)||0)});
  return r;
}
function setGeneratorDiagProgress(st){
  var box=document.getElementById('avdiagprogress');if(!box)return;
  box.hidden=false;
  var stage=document.getElementById('avdiagstage');if(stage)stage.textContent=st.stage||'Working…';
  var pct=document.getElementById('avdiagpct');if(pct)pct.textContent=Math.round(st.percent||0)+'%';
  var elapsed=document.getElementById('avdiagelapsed');if(elapsed)elapsed.textContent='Elapsed: '+Math.round(st.elapsed||0)+'s';
  var rail=box.querySelector('.avdiagprogressrail'),bar=box.querySelector('.avdiagprogressbar');
  if(rail)rail.setAttribute('aria-valuenow',String(Math.round(st.percent||0)));
  if(bar)bar.style.width=Math.round(st.percent||0)+'%';
}
function runGeneratorDiagnostic(selector,button){
  A.generatorDiagToken=(A.generatorDiagToken||0)+1;var token=A.generatorDiagToken;
  var out=document.getElementById('avdiag');
  if(out)out.textContent='Starting AirVPN generator/profile diagnostic…\nNo VPN Dashboard changes will be made.';
  setGeneratorDiagProgress({percent:1,stage:'Starting diagnostic job…',elapsed:0});
  rpc('generator_diag_start',{selector:selector||''}).then(function(r){
    var job=String((r&&r.output)||'').trim().split(/\r?\n/).pop();
    if(!/^diag-[0-9]+-[0-9]+$/.test(job))throw Error('Diagnostic did not return a valid job ID: '+String((r&&r.output)||''));
    function poll(){
      if(token!==A.generatorDiagToken)return Promise.resolve();
      return rpc('generator_diag_status',{job:job}).then(function(s){
        if(token!==A.generatorDiagToken)return;
        var st=parseGeneratorDiagStatus((s&&s.output)||'');setGeneratorDiagProgress(st);
        if(out&&st.output)out.textContent=st.output;
        if(st.state==='complete'||st.state==='failed'){
          if(button)button.disabled=false;
          if(st.state==='failed'&&out)out.textContent=(st.output||'')+'\n\nDiagnostic job failed: '+st.stage;
          return;
        }
        return new Promise(function(resolve){setTimeout(resolve,900)}).then(poll);
      });
    }
    return poll();
  }).catch(function(err){
    setGeneratorDiagProgress({percent:100,stage:'Diagnostic failed',elapsed:0});
    if(out)out.textContent='Generator diagnostic error: '+err.message;
    if(button)button.disabled=false;
  });
}
function act(e){
  var trig=e.target.closest('[data-select-menu]');
  if(trig){
    e.preventDefault();e.stopPropagation();
    var key=trig.dataset.selectMenu||'';
    var panel=document.querySelector('[data-select-menu-panel="'+CSS.escape(key)+'"]');
    if(panel){
      var opening=!panel.classList.contains('open');
      closeSelectMenus(panel);
      panel.classList.toggle('open',opening);
      var row=panel.closest('tr'),cell=panel.closest('td');
      if(row)row.classList.toggle('avmenurow',opening);
      if(cell)cell.classList.toggle('avmenucell',opening);
    }
    return;
  }
  var ra=e.target.closest('[data-server-action]');
  if(ra){
    e.preventDefault();e.stopPropagation();
    var key=ra.dataset.serverKey||'',r=findCatalogRowByKey(key);
    if(!r){
      var bad=document.getElementById('avmsg')||document.getElementById('avcatalogmeta');
      if(bad)bad.textContent='Server action failed: the selected row is no longer in the current catalog.';
      return;
    }
    var action=ra.dataset.serverAction;
    if(action==='info'){showServerInfo(r);return}
    if(action==='add-profile'){closeSelectMenus();if(A.profileMutationBusy){showProfileResultPrompt(false,'BUSY — AirVPN operation in progress',profileBusyMessage());return}setServerAsSelector(r).catch(function(){});return}
    if(action==='connect'){
      closeSelectMenus();
      if(A.profileMutationBusy){showProfileResultPrompt(false,'BUSY — AirVPN operation in progress',profileBusyMessage());return}
      if(!confirm('Connect to '+r[0]+' now? The profile will be generated/applied, a rollback backup will be created, and the mapped GL.iNet tunnel will be enabled if available.'))return;
      var msg=document.getElementById('avmsg')||document.getElementById('avcatalogmeta');
      setProfileMutationBusy(true,'Connecting to '+r[0]);
      if(msg)msg.textContent='Connecting to '+r[0]+'… generating profile, enabling the GL.iNet tunnel, and waiting for a WireGuard handshake.';
      rpc('sync_connect',{selector:r[0]}).then(function(res){
        if(msg)msg.textContent=(res&&res.output)||('Connected to '+r[0]+'.');
        refreshVpnPower();
        setTimeout(refreshVpnPower,1500);
        setTimeout(refreshVpnPower,5000);
        A.selectedServer=String(r[0]||'');
        makeServerTable('avcatalogtable',A.catalogRows,true);
      }).catch(function(err){
        if(isBackendBusyError(err)){
          if(msg)msg.textContent='BUSY: '+err.message;
          showProfileResultPrompt(false,'BUSY — AirVPN operation in progress',err.message);
        }else if(msg)msg.textContent='Connect Now failed: '+err.message;
        refreshVpnPower();
        setTimeout(refreshVpnPower,1500);
      }).then(function(){setProfileMutationBusy(false)},function(){setProfileMutationBusy(false)});
      return;
    }
  }
  var cl=e.target.closest('[data-server-close]');if(cl){e.preventDefault();closeServerModal();return}
  var th=e.target.closest('th[data-sort]');
  if(th){
    toggleCatalogSort(th.dataset.sort);
    return;
  }
  var b=e.target.closest('[data-a]');if(!b)return;
  var a=b.dataset.a,m=document.getElementById('avmsg');b.disabled=true;var p;
  if(a==='detect-devices'){
    var ds=document.getElementById('avdevstatus'),di=document.getElementById('avd'),dl=document.getElementById('avdevlist');
    if(ds)ds.textContent='Reading devices from AirVPN…';
    p=rpc('devices',{}).then(function(r){
      var raw=r&&r.output,obj=raw;
      if(typeof raw==='string'){try{obj=JSON.parse(raw)}catch(_){obj={}}}
      var devs=(obj&&Array.isArray(obj.devices))?obj.devices:[];
      if(dl)dl.innerHTML=devs.map(function(d){return '<option value="'+E(d.name||d.id||'')+'">'+E(d.id||'')+'</option>'}).join('');
      if(!devs.length)throw Error('AirVPN returned no registered devices for this account.');
      if(devs.length===1){
        var d=devs[0],name=String(d.name||d.id||'');if(di)di.value=name;
        if(ds)ds.textContent='Detected one AirVPN device: '+name+' (id='+String(d.id||'')+'). It has been selected; click Save to persist it.';
      }else{
        if(ds)ds.textContent='Detected '+devs.length+' devices: '+devs.map(function(d){return String(d.name||d.id||'')}).join(', ')+'. Choose one from the field, then click Save.';
      }
    }).catch(function(err){if(ds)ds.textContent='Device detection failed: '+err.message;throw err;});
  }
  if(a==='save')p=save().then(function(r){m.textContent='AirVPN settings saved.'+(r&&r.keySaved?' API key was committed to OpenWrt UCI and verified by read-back.':'')});
  if(a==='preview')p=save().then(function(){return rpc('filtered_servers',{selector:first()})}).then(function(r){m.textContent='Filtered/sorted AirVPN servers for '+first();table(r.output||'')});
  if(a==='catalog')p=loadCatalog(true);
  else if(a==='vpn-power'){
    var b=document.getElementById('avvpnpower'),turnOn=!(b&&b.dataset.on==='1');
    var profiles=Number(b&&b.dataset.profiles)||0;
    if(turnOn&&profiles<1){
      var notice=document.getElementById('avpowernotice');
      var msg='No VPN Profiles to activate. Select an AirVPN server and choose Add server to profile or Connect Now first.';
      if(notice)notice.textContent=msg;
      var meta=document.getElementById('avcatalogmeta');if(meta)meta.textContent=msg;
      if(b){b.disabled=false;b.title='No AirVPN VPN profiles are available to activate';b.focus();}
      return;
    }
    if(b){b.disabled=true;b.textContent=turnOn?'Turning VPN On…':'Turning VPN Off…';}
    p=rpc('vpn_power_set',{state:turnOn?'on':'off'}).then(function(r){
      return refreshVpnPower().then(function(){
        setTimeout(refreshVpnPower,1500);
        setTimeout(refreshVpnPower,5000);
        var m=document.getElementById('avcatalogmeta');
        if(m&&r&&r.output)m.textContent=String(r.output).split('\n')[0];
      });
    }).catch(function(err){
      refreshVpnPower();
      setTimeout(refreshVpnPower,1500);
      var m=document.getElementById('avcatalogmeta');
      if(m)m.textContent='VPN toggle failed: '+err.message;
    });
  }
  else if(a==='best'){
    var br=bestServerRow();
    if(br){
      p=setServerAsSelector(br).then(function(){
        var bm=document.getElementById('avcatalogmeta');
        if(bm)bm.textContent='Best server added to profile: '+br[0]+' (Smart Rank '+smartRankValue(br).toFixed(2)+').';
      });
    }else{
      if(m)m.textContent='No currently listed AirVPN server is available.';
      b.disabled=false;return;
    }
  }
  else if(a==='latency'){b.disabled=false;testTopLatency();return;}
  else if(a==='latency-all'){b.disabled=false;testAllLatency();return;}
  else if(a==='latency-basic'){setLatencyVerbosity(false);b.disabled=false;return;}
  else if(a==='latency-details'){setLatencyVerbosity(true);b.disabled=false;return;}
  else if(a==='gen-diag'){var ds=v('avdiagserver')||'';runGeneratorDiagnostic(ds,b);return;}
  else if(a==='validate'){p=rpc('connection_validate',{}).then(function(r){document.getElementById('avdiag').textContent=(r&&r.output)||'No validation output.'});}
  else if(a==='selftest'){p=rpc('self_test',{}).then(function(r){document.getElementById('avdiag').textContent=(r&&r.output)||'No self-test output.'});}
  else if(a==='diag'){p=rpc('diagnostics_export',{}).then(function(r){var out=(r&&r.output)||'';document.getElementById('avdiag').textContent=out;downloadText('airvpn-native-diagnostics.txt',out);});}
  else if(a==='rollback'){if(confirm('Restore the last-known-good VPN configuration?'))p=rpc('rollback',{}).then(function(r){document.getElementById('avdiag').textContent=(r&&r.output)||'Rollback complete.'});}
  else if(a==='apply-sort'){
    var sc=v('avsort')||'smart_rank',sd=v('avdir')||'desc';
    A.catalogSort={column:sc,direction:sd};
    if(A.catalogRows&&A.catalogRows.length)sortCatalogInMemory(sc,sd);
    setSortApplyEnabled(false);
    p=saveConfigOnly({sort_column:sc,sort_direction:sd});
  }
  else if(a==='fit-columns'){
    A.fitColumns=!A.fitColumns;
    var fit=document.getElementById('avfitcolumns');
    if(fit)fit.textContent=A.fitColumns?'Show All Columns':'Fit Columns';
    makeServerTable('avcatalogtable',A.catalogRows,true);
    var meta=document.getElementById('avcatalogmeta');
    if(meta)meta.textContent=A.fitColumns?'Fit view enabled — lower-priority columns are hidden automatically when space is tight.':'All user-enabled columns shown — use Fit Columns to optimize the AirVPN page width.';
    b.disabled=false;return;
  }
  else if(a==='apply-columns'){
    p=applyColumnOptions().then(function(){
      var menu=document.querySelector('#airvpn-provider-view details.avcolumns');
      if(menu)menu.open=false;
    });
  }
  else if(a==='reset-columns'){
    A.columnOrder=AV_DEFAULT_COLUMN_ORDER.slice();
    A.hiddenColumns={};
    var co=document.getElementById('avcolorder');if(co)co.value=A.columnOrder.join(',');
    var hc=document.getElementById('avhiddencols');if(hc)hc.value='';
    setColumnOptionCheckboxes();
    makeServerTable('avcatalogtable',A.catalogRows,true);
    p=saveConfigOnly().then(function(){
      var meta=document.getElementById('avcatalogmeta');
      if(meta)meta.textContent='Column order and visibility reset to defaults.';
      var menu=document.querySelector('#airvpn-provider-view details.avcolumns');
      if(menu)menu.open=false;
    });
  }
  if(a==='sync')p=save().then(function(){m.textContent='Synchronizing AirVPN profiles…';return rpc('sync')}).then(function(r){m.textContent=r.output||'Profiles synchronized.'});
  if(a==='cache')p=rpc('clear_cache').then(function(r){m.textContent=r.output||'Cache cleared.'});
  Promise.resolve(p).catch(function(x){m.textContent='AirVPN error: '+x.message}).finally(function(){b.disabled=false})
}

function tick(){
  A.debug=A.debug||{};
  var ref=sidebarReference();
  if(!ref){
    if(A.mode)positionAirSidebarView();
    return;
  }
  var item=installSidebarItem(ref);
  if(!item)return;
  A.sidebarRoot=sidebarContainer(item);
  if(A.mode){markSidebarActive(true);positionAirSidebarView();return}
  if(wantsAirVPN()){
    clearTimeout(A.sidebarRestoreTimer);
    A.sidebarRestoreTimer=setTimeout(function(){
      var live=document.getElementById('airvpn-sidebar-item');
      if(live&&wantsAirVPN()&&!A.mode)showAirSidebar(live);
    },90);
  }
}
var mo=new MutationObserver(function(){clearTimeout(A.tm);A.tm=setTimeout(tick,180)});
function start(){
  if(document.body){
    mo.observe(document.body,{subtree:true,childList:true,attributes:true});
    document.addEventListener('click',sidebarNavigationCapture,true);
    window.addEventListener('resize',function(){if(A.mode)positionAirSidebarView()});
    tick();
    setInterval(tick,750);
  }else setTimeout(start,100)
}
start();
window.addEventListener('hashchange',function(){if(A.mode&&A.airvpnBaseHash!==location.hash)restore(true);setTimeout(tick,250)});
window.addEventListener('pageshow',function(){setTimeout(tick,80)});
window.addEventListener('load',function(){setTimeout(tick,80)});
document.addEventListener('visibilitychange',function(){if(!document.hidden)setTimeout(tick,80)});
})();