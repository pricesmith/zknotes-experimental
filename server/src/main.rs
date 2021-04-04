mod config;
mod email;
mod interfaces;
mod search;
mod sqldata;
mod sqltest;
mod util;

use actix_files::NamedFile;
use actix_session::{CookieSession, Session};
use actix_web::middleware::Logger;
use actix_web::{middleware, web, App, HttpRequest, HttpResponse, HttpServer, Result};
use chrono;
use clap::{Arg, SubCommand};
use config::Config;
use log::{debug, error, info, log_enabled, Level};
use serde_json;
use std::error::Error;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use timer;
use uuid::Uuid;
use zkprotocol::messages::{PublicMessage, ServerResponse, UserMessage};

fn favicon(_req: &HttpRequest) -> Result<NamedFile> {
  let stpath = Path::new("static/favicon.ico");
  Ok(NamedFile::open(stpath)?)
}

fn sitemap(_req: &HttpRequest) -> Result<NamedFile> {
  let stpath = Path::new("static/sitemap.txt");
  Ok(NamedFile::open(stpath)?)
}

// simple index handler
fn mainpage(session: Session, data: web::Data<Config>, req: HttpRequest) -> HttpResponse {
  info!("remote ip: {:?}, request:{:?}", req.connection_info(), req);

  // logged in?
  let logindata = match interfaces::login_data_for_token(session, &data) {
    Ok(Some(logindata)) => serde_json::to_value(logindata).unwrap_or(serde_json::Value::Null),
    _ => serde_json::Value::Null,
  };

  match util::load_string("static/index.html") {
    Ok(s) => {
      // search and replace with logindata!
      HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(s.replace("{{logindata}}", logindata.to_string().as_str()))
    }
    Err(e) => {
      println!("err");
      HttpResponse::from_error(actix_web::error::ErrorImATeapot(e))
    }
  }
}

fn public(
  data: web::Data<Config>,
  item: web::Json<PublicMessage>,
  _req: HttpRequest,
) -> HttpResponse {
  info!("public msg: {:?}", &item);

  match interfaces::public_interface(&data, item.into_inner()) {
    Ok(sr) => HttpResponse::Ok().json(sr),
    Err(e) => {
      error!("'public' err: {:?}", e);
      let se = ServerResponse {
        what: "server error".to_string(),
        content: serde_json::Value::String(e.to_string()),
      };
      HttpResponse::Ok().json(se)
    }
  }
}

fn user(
  session: Session,
  data: web::Data<Config>,
  item: web::Json<UserMessage>,
  _req: HttpRequest,
) -> HttpResponse {
  info!("user msg: {}, {:?}", &item.what, &item.data);
  match interfaces::user_interface(&session, &data, item.into_inner()) {
    Ok(sr) => HttpResponse::Ok().json(sr),
    Err(e) => {
      error!("'user' err: {:?}", e);
      let se = ServerResponse {
        what: "server error".to_string(),
        content: serde_json::Value::String(e.to_string()),
      };
      HttpResponse::Ok().json(se)
    }
  }
}

fn register(data: web::Data<Config>, req: HttpRequest) -> HttpResponse {
  info!("registration: uid: {:?}", req.match_info().get("uid"));
  match (req.match_info().get("uid"), req.match_info().get("key")) {
    (Some(uid), Some(key)) => {
      // read user record.  does the reg key match?
      match sqldata::read_user(data.db.as_path(), uid) {
        Ok(user) => {
          if user.registration_key == Some(key.to_string()) {
            let mut mu = user;
            mu.registration_key = None;
            match sqldata::connection_open(data.db.as_path())
              .and_then(|conn| sqldata::update_user(&conn, &mu))
            {
              Ok(_) => HttpResponse::Ok().body(
                format!(
                  "<h1>You are registered!<h1> <a href=\"{}\">\
                 Proceed to the main site</a>",
                  data.mainsite
                )
                .to_string(),
              ),
              Err(_e) => HttpResponse::Ok().body("<h1>registration failed</h1>".to_string()),
            }
          } else {
            HttpResponse::Ok().body("<h1>registration failed</h1>".to_string())
          }
        }
        Err(_e) => HttpResponse::Ok().body("registration key or user doesn't match".to_string()),
      }
    }
    _ => HttpResponse::Ok().body("Uid, key not found!".to_string()),
  }
}

fn defcon() -> Config {
  Config {
    ip: "127.0.0.1".to_string(),
    port: 8000,
    createdirs: false,
    db: PathBuf::from("./mahbloag.db"),
    mainsite: "https:://mahbloag.practica.site/".to_string(),
    appname: "mahbloag".to_string(),
    domain: "practica.site".to_string(),
    admin_email: "admin@practica.site".to_string(),
    token_expiration_ms: 7 * 24 * 60 * 60 * 1000, // 7 days in milliseconds
  }
}

fn purge_tokens(dbfile: &Path, token_expiration_ms: i64) -> Result<(), Box<dyn Error>> {
  let conn = sqldata::connection_open(dbfile)?;

  sqldata::purge_tokens(&conn, token_expiration_ms)?;

  Ok(())
}

fn load_config() -> Config {
  match util::load_string("config.toml") {
    Err(e) => {
      error!("error loading config.toml: {:?}", e);
      defcon()
    }
    Ok(config_str) => match toml::from_str(config_str.as_str()) {
      Ok(c) => c,
      Err(e) => {
        error!("error loading config.toml: {:?}", e);
        defcon()
      }
    },
  }
}

fn main() {
  match err_main() {
    Err(e) => error!("error: {:?}", e),
    Ok(_) => (),
  }
}

#[actix_web::main]
async fn err_main() -> Result<(), Box<dyn Error>> {
  let matches = clap::App::new("zknotes server")
    .version("1.0")
    .author("Ben Burdette")
    .about("Does awesome things")
    .arg(
      Arg::with_name("export")
        .short("e")
        .long("export")
        .value_name("FILE")
        .help("Export database to json")
        .takes_value(true),
    )
    .get_matches();

  // are we exporting the DB?
  match matches.value_of("export") {
    Some(exportfile) => {
      // do that exporting...
      let config = load_config();

      sqldata::dbinit(config.db.as_path(), config.token_expiration_ms)?;

      util::write_string(
        exportfile,
        serde_json::to_string_pretty(&sqldata::export_db(config.db.as_path())?)?.as_str(),
      )?;

      Ok(())
    }
    None => {
      // normal server ops
      env_logger::init();

      info!("server init!");

      let config = load_config();

      info!("config: {:?}", config);

      sqldata::dbinit(config.db.as_path(), config.token_expiration_ms)?;

      let timer = timer::Timer::new();

      let ptconfig = config.clone();

      let guard = timer.schedule_repeating(chrono::Duration::days(1), move || {
        match purge_tokens(ptconfig.db.as_path(), ptconfig.token_expiration_ms) {
          Err(e) => error!("purge_tokens error: {}", e),
          Ok(_) => (),
        }
      });

      let c = config.clone();
      HttpServer::new(move || {
        App::new()
          .data(c.clone()) // <- create app with shared state
          .wrap(middleware::Logger::default())
          .wrap(
            CookieSession::signed(&[0; 32]) // <- create cookie based session middleware
              .secure(false) // allows for dev access
              .max_age(10 * 24 * 60 * 60), // 10 days
          )
          .service(web::resource("/public").route(web::post().to(public)))
          .service(web::resource("/user").route(web::post().to(user)))
          .service(web::resource(r"/register/{uid}/{key}").route(web::get().to(register)))
          .service(actix_files::Files::new("/static/", "static/"))
          .service(web::resource("/{tail:.*}").route(web::get().to(mainpage)))
      })
      .bind(format!("{}:{}", config.ip, config.port))?
      .run()
      .await?;

      Ok(())
    }
  }
}
