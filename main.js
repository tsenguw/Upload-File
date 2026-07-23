const { app, BrowserWindow } = require("electron");
const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");
const os = require("os");
const tar = require("tar");

let n8nProcess;

const resourceRoot =
    app.isPackaged
        ? process.resourcesPath
        : __dirname;

async function extractTarGz(
    tarFile,
    outputDir
){

    if(!fs.existsSync(outputDir)){

        fs.mkdirSync(
            outputDir,
            {
                recursive:true
            }
        );

    }


    console.log(
        "Extract:",
        tarFile
    );


    await tar.x({

        file: tarFile,

        cwd: outputDir,

        gzip:true,

        preservePaths:false

    });


    console.log(
        "Extract complete"
    );

}

async function prepareRuntime(){

    const userRoot =
        path.join(
            os.homedir(),
            "AppData",
            "Local",
            "MyN8N"
        );


    const nodePath =
        path.join(
            userRoot,
            "node.exe"
        );


    const n8nPath =
        path.join(
            userRoot,
            "node_modules",
            "n8n",
            "bin",
            "n8n"
        );



    if(!fs.existsSync(nodePath)){


        await extractTarGz(

            path.join(
                resourceRoot,
                "runtime.tar.gz"
            ),

            userRoot

        );

    }



    if(!fs.existsSync(n8nPath)){


        await extractTarGz(

            path.join(
                resourceRoot,
                "n8n.tar.gz"
            ),

            userRoot

        );

    }

}

function startN8N(){
    const userRoot = path.join(
        os.homedir(),
        "AppData",
        "Local",
        "MyN8N"
    );

    const nodePath = path.join(userRoot, "node.exe");

    const n8nPath =
        path.join(
            userRoot,
            "node_modules",
            "n8n",
            "bin",
            "n8n"
        );


    process.env.N8N_USER_FOLDER =
        path.join(userRoot,"data");


    n8nProcess = spawn(
        nodePath,
        [n8nPath],
        {
            cwd:userRoot,
            windowsHide:false,
            detached:false
        }
    );

    n8nProcess.on(
        "exit",
        (code)=>{
            console.log(
                "n8n stopped:",
                code
            );
        }
    );

    n8nProcess.stdout.on(
        "data",
        d=>console.log(d.toString())
    );


    n8nProcess.stderr.on(
        "data",
        d=>console.log(d.toString())
    );
}



function createWindow(){

    const win =
        new BrowserWindow({
            width:1200,
            height:800
        });


    waitN8N(win);

}



function waitN8N(win){

    const http=require("http");


    let timer=setInterval(()=>{

        http.get(
            "http://localhost:5678/healthz",
            res=>{

                if(res.statusCode===200){

                    clearInterval(timer);

                    win.loadURL(
                        "http://localhost:5678"
                    );

                }

            }
        ).on(
            "error",
            ()=>{}
        );


    },3000);

}

app.whenReady()
.then(async()=>{
    await prepareRuntime();
    startN8N();
    createWindow();
});

app.on(
"before-quit",
()=>{
    if(n8nProcess){
        try{

            n8nProcess.kill(
                "SIGTERM"
            );

        }
        catch(e){
            console.log(e);

        }
    }
});