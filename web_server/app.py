from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from db import connect_db, close_db
from models.student import (
    StudentCreate,
    StudentProfile,
    StudentUpdate,
    create_student,
    get_student,
    update_student,
    delete_student,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect_db()
    yield
    await close_db()


app = FastAPI(title="RaikeShacks API", lifespan=lifespan)


@app.post("/students", response_model=StudentProfile, status_code=201)
async def add_student(body: StudentCreate):
    return await create_student(body)


@app.get("/students/{uid}", response_model=StudentProfile)
async def read_student(uid: str):
    student = await get_student(uid)
    if student is None:
        raise HTTPException(status_code=404, detail="Student not found")
    return student


@app.put("/students/{uid}", response_model=StudentProfile)
async def edit_student(uid: str, body: StudentUpdate):
    student = await update_student(uid, body)
    if student is None:
        raise HTTPException(status_code=404, detail="Student not found")
    return student


@app.delete("/students/{uid}", status_code=204)
async def remove_student(uid: str):
    deleted = await delete_student(uid)
    if not deleted:
        raise HTTPException(status_code=404, detail="Student not found")
