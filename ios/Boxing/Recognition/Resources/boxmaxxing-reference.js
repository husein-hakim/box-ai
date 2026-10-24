// GENERATED from retained raw-instruction replay. Run build_ios_reference.py to regenerate.
(function(){
const source={functions:{}};
const shapes=new WeakMap();
function addFunctions(extra){Object.assign(source.functions,extra.functions);}
function numeric(value){if(value && typeof value === "object" && "$undefined" in value)return undefined;return value && typeof value === "object" && "$number" in value ? Number(value.$number.replace("inf","Infinity")) : value;}
function replay(id,parameters,self,env={},newTarget) {
 const fn=source.functions[id],r=[],byPC=new Map(fn.instructions.map((row,i)=>[row.pc,i]));let pc=0,steps=0;
 const globals={Float32Array,Math,Number,Object,Array,Set,Map,Infinity,console,HermesInternal:{concat:(...args)=>args.map(String).join('')}};
 while(true) {
  if(++steps>50000000)throw Error(`Replay instruction budget ${id}`);
  const {op,a,key,keys,values,pc:address}=fn.instructions[pc++];
  const v=i=>r[a[i]];const jump=()=>{pc=byPC.get(address+a[0]);if(pc===undefined)throw Error('Invalid branch');};
  switch(op) {
   case 'GetParentEnvironment':{let parent=env;for(let n=0;n<a[1];n++)parent=parent.parent;r[a[0]]=parent;break;}
   case 'CreateTopLevelEnvironment':r[a[0]]={};break;
   case 'CreateEnvironment':r[a[0]]={parent:v(1)};break;
   case 'CreateFunctionEnvironment':r[a[0]]={parent:env};break;
   case 'StoreToEnvironment':case 'StoreNPToEnvironment':v(0)[a[1]]=v(2);break;
   case 'CreateClosure':{const closureEnv=v(1);r[a[0]]=function(...args){return replay(a[2],args,this,closureEnv);};break;}
   case 'LoadFromEnvironment':r[a[0]]=v(1)[a[2]];break;
   case 'LoadParam':r[a[0]]=a[1]===0?self:parameters[a[1]-1];break;
   case 'GetNewTarget':r[a[0]]=newTarget;break;
   case 'CreateBaseClass':{const captured=v(2),target=a[3];const ctor=function(...args){return replay(target,args,this,captured,new.target);};r[a[0]]=ctor;r[a[1]]=ctor.prototype;break;}
   case 'GetGlobalObject':r[a[0]]=globals;break;
   case 'GetById':case 'GetByIdShort':case 'TryGetById':r[a[0]]=v(1)[key];break;
   case 'GetByVal':if(v(1)==null)throw Error(`Null indexed receiver ${id}@${address} key=${v(2)}`);r[a[0]]=v(1)[v(2)];break;
   case 'GetByIndex':r[a[0]]=v(1)[a[2]];break;
   case 'Mov':r[a[0]]=v(1);break;
   case 'NewObject':r[a[0]]={};break;
   case 'NewArrayWithBuffer':case 'NewArrayWithBufferLong':r[a[0]]=values.map(numeric);break;
   case 'DefineOwnByVal':v(0)[v(2)]=v(1);break;
   case 'DefineOwnById':case 'DefineOwnByIdLong':v(0)[key]=v(1);break;
   case 'DefineOwnGetterSetterByVal':Object.defineProperty(v(0),v(1),{get:v(2),set:v(3),configurable:true});break;
   case 'NewArray':r[a[0]]=[];break;
   case 'DefineOwnInDenseArray':v(0)[a[2]]=v(1);break;
   case 'PutByIdStrictLong':case 'PutByIdStrict':v(0)[key]=v(1);break;
   case 'LoadConstFalse':r[a[0]]=false;break;
   case 'LoadConstTrue':r[a[0]]=true;break;
   case 'Not':r[a[0]]=!v(1);break;
   case 'Negate':r[a[0]]=-v(1);break;
   case 'LoadConstZero':r[a[0]]=0;break;
   case 'LoadConstUInt8':case 'LoadConstInt':r[a[0]]=a[1];break;
   case 'LoadConstDouble':r[a[0]]=typeof a[1]==='string'?Number(a[1]):a[1];break;
   case 'LoadConstString':case 'LoadConstStringLongIndex':r[a[0]]=key;break;
   case 'LoadConstNull':r[a[0]]=null;break;
   case 'LoadConstUndefined':r[a[0]]=undefined;break;
   case 'Add':case 'AddN':r[a[0]]=v(1)+v(2);break;
   case 'Sub':case 'SubN':r[a[0]]=v(1)-v(2);break;
   case 'MulN':case 'Mul':r[a[0]]=v(1)*v(2);break;
   case 'Mod':r[a[0]]=v(1)%v(2);break;
   case 'DivN':case 'Div':r[a[0]]=v(1)/v(2);break;
   case 'RShift':r[a[0]]=v(1)>>v(2);break;
   case 'Inc':r[a[0]]=v(1)+1;break;
   case 'IsIn':r[a[0]]=v(1) in v(2);break;
   case 'Neq':r[a[0]]=v(1)!=v(2);break;
   case 'Eq':r[a[0]]=v(1)==v(2);break;
   case 'StrictNeq':r[a[0]]=v(1)!==v(2);break;
   case 'StrictEq':r[a[0]]=v(1)===v(2);break;
   case 'Less':r[a[0]]=v(1)<v(2);break;
   case 'Greater':r[a[0]]=v(1)>v(2);break;
   case 'LessEq':r[a[0]]=v(1)<=v(2);break;
   case 'GreaterEq':r[a[0]]=v(1)>=v(2);break;
   case 'Jmp':case 'JmpLong':jump();break;
   case 'JmpTrue':case 'JmpTrueLong':if(v(1))jump();break;
   case 'JmpFalse':case 'JmpFalseLong':if(!v(1))jump();break;
   case 'JLess':case 'JLessLong':case 'JLessN':if(v(1)<v(2))jump();break;
   case 'JNotLessNLong':case 'JNotLess':if(!(v(1)<v(2)))jump();break;
   case 'JNotGreaterEqualLong':case 'JNotGreaterEqual':if(!(v(1)>=v(2)))jump();break;
   case 'JGreaterLong':case 'JGreater':if(v(1)>v(2))jump();break;
   case 'JNotGreaterLong':case 'JNotGreater':if(!(v(1)>v(2)))jump();break;
   case 'JLessEqualLong':case 'JLessEqualN':case 'JLessEqual':if(v(1)<=v(2))jump();break;
   case 'JNotLessEqualN':case 'JNotLessEqual':if(!(v(1)<=v(2)))jump();break;
   case 'JGreaterEqual':if(v(1)>=v(2))jump();break;
   case 'JEqual':case 'JEqualLong':if(v(1)==v(2))jump();break;
   case 'JNotEqual':case 'JNotEqualLong':if(v(1)!=v(2))jump();break;
   case 'JStrictEqual':case 'JStrictEqualLong':if(v(1)===v(2))jump();break;
   case 'JStrictNotEqualLong':case 'JStrictNotEqual':if(v(1)!==v(2))jump();break;
   case 'JmpTypeOfIs':if(a[2]===128&&typeof v(1)==='function')jump();else throw Error('Unsupported type check');break;
   case 'PutByValStrict':v(0)[v(1)]=v(2);break;
   case 'CreateThisForNew':r[a[0]]={};break;
   case 'Construct':r[a[0]]=Reflect.construct(v(1),Array.from({length:a[2]-1},(_,i)=>r[fn.frameSize-9-i]));break;
   case 'SelectObject':r[a[0]]=v(2)&&(typeof v(2)==='object'||typeof v(2)==='function')?v(2):v(1);break;
   case 'Call4':r[a[0]]=v(1).call(v(2),v(3),v(4),v(5));break;
   case 'CallBuiltin':{const args=Array.from({length:a[2]-1},(_,i)=>r[fn.frameSize-9-i]);
    switch(a[1]){
     case 44:throw TypeError(args[0]);
     case 46:{const [target,from]=args;r[a[0]]=Object.assign(target,from);break;}
     case 48:{const [target,from,offset]=args;let index=offset;for(const value of from)target[index++]=value;r[a[0]]=index;break;}
     case 49:r[a[0]]=Reflect.apply(args[0],args[2],args[1]);break;
     default:throw Error('Unsupported builtin '+a[1]);
    }break;}
   case 'Call1':r[a[0]]=v(1).call(v(2));break;
   case 'Call2':r[a[0]]=v(1).call(v(2),v(3));break;
   case 'Call3':r[a[0]]=v(1).call(v(2),v(3),v(4));break;
   case 'Call':r[a[0]]=v(1).apply(r[fn.frameSize-8],Array.from({length:a[2]-1},(_,i)=>r[fn.frameSize-9-i]));break;
   case 'NewObjectWithBufferAndParent':case 'NewObjectWithBuffer':case 'NewObjectWithBufferLong':{
    const obj=op==='NewObjectWithBufferAndParent'?Object.create(v(1)):{};for(let i=0;i<keys.length;i++)obj[keys[i]]=numeric(values[i]);shapes.set(obj,keys);r[a[0]]=obj;break;}
   case 'PutOwnBySlotIdx':v(0)[shapes.get(v(0))[a[2]]]=v(1);break;
   case 'IteratorBegin':r[a[0]]=v(1)[Symbol.iterator]();break;
   case 'IteratorNext':{const result=v(1).next();r[a[0]]=result.value;if(result.done)r[a[1]]=undefined;break;}
   case 'IteratorClose':break;
   case 'Throw':throw v(0);
   case 'Ret':return v(0);
   default:throw Error(`Unsupported ${id} ${address}: ${op}`);
  }
 }
}
function classifierReference(weights,input) {
 const env={0:{CLASSES:weights.classes},1:x=>x>0?x:0};
 env[2]=(x,t,cin,l)=>replay(28403,[x,t,cin,l],undefined,env);
 const self={weights,t:weights.t,f:weights.f};
 self.logits=x=>replay(28407,[x],self,env);
 const logits=Array.from(self.logits(Float32Array.from(input)));
 const result=replay(28408,[Float32Array.from(input)],self,env);
 return {logits,probabilities:Array.from(result.probs),classIndex:weights.classes.indexOf(result.cls)};
}


let data, pipeline, responseJudge;const cache=new Map();
function loadModule(id){
 if(cache.has(id))return cache.get(id).exports;
 const registration=data.modules[id];if(!registration)throw Error('External dependency forbidden: '+id);
 const module={exports:{}};cache.set(id,module);
 replay(registration.function,[{},loadModule,undefined,undefined,module,module.exports,registration.dependencies]);
 return module.exports;
}
globalThis.boxKernel={
 initialize:function(payload){
  data=JSON.parse(payload);addFunctions(data);cache.clear();
  const module=loadModule(4765);
  pipeline=new module.PadPipeline(module.DEFAULT_PIPELINE,{classifier:{classify:function(input){
   const result=boxClassify(Array.from(input));if(result.error)throw Error(result.error);return result;
  }}});
  responseJudge=new (loadModule(4372).StepJudge)({stance:'orthodox'});
  return true;
 },
 judge:function(method,argumentsJSON){
  const allowed=['open','padReady','observe','tick','suspend','resume','close','reset','summary','view'];
  if(!allowed.includes(method))throw Error('Unsupported judge method');
  const value=typeof responseJudge[method]==='function'?responseJudge[method](...JSON.parse(argumentsJSON)):responseJudge[method];
  return JSON.stringify(value===undefined?null:value);
 },
 push:function(frame){return JSON.stringify(pipeline.push(JSON.parse(frame)));},
 reset:function(){pipeline.reset();return true;},
 setStance:function(stance){pipeline.setStance(stance);responseJudge.setStance(stance);return true;},
 defaults:function(){return JSON.stringify(loadModule(4765).DEFAULT_PIPELINE);}
};

})();
